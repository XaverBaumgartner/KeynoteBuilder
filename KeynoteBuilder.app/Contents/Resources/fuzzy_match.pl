#!/usr/bin/perl
use strict;
use warnings;
use File::Glob ':bsd_glob';
use File::Basename;
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);

# --- Jaro-Winkler similarity ---

sub jaro_winkler {
    my ($s1, $s2) = @_;
    my $n = length($s1);
    my $m = length($s2);
    return 1.0 if $n == 0 && $m == 0;
    return 0.0 if $n == 0 || $m == 0;

    my $match_window = int((($n > $m ? $n : $m) / 2)) - 1;
    $match_window = 0 if $match_window < 0;

    my @s1_matched = (0) x $n;
    my @s2_matched = (0) x $m;

    my $matches = 0;
    my $transpositions = 0;

    for my $i (0 .. $n - 1) {
        my $lo = $i - $match_window;
        $lo = 0 if $lo < 0;
        my $hi = $i + $match_window;
        $hi = $m - 1 if $hi >= $m;
        for my $j ($lo .. $hi) {
            next if $s2_matched[$j];
            next if substr($s1, $i, 1) ne substr($s2, $j, 1);
            $s1_matched[$i] = 1;
            $s2_matched[$j] = 1;
            $matches++;
            last;
        }
    }
    return 0.0 if $matches == 0;

    my $k = 0;
    for my $i (0 .. $n - 1) {
        next unless $s1_matched[$i];
        $k++ until $s2_matched[$k];
        $transpositions++ if substr($s1, $i, 1) ne substr($s2, $k, 1);
        $k++;
    }

    my $jaro = ($matches / $n + $matches / $m + ($matches - $transpositions / 2) / $matches) / 3;

    my $prefix = 0;
    my $max_prefix = 4;
    $max_prefix = $n if $n < $max_prefix;
    $max_prefix = $m if $m < $max_prefix;
    for my $i (0 .. $max_prefix - 1) {
        last if substr($s1, $i, 1) ne substr($s2, $i, 1);
        $prefix++;
    }

    return $jaro + $prefix * 0.1 * (1 - $jaro);
}

# --- File hashing ---

sub hash_file {
    my ($path) = @_;
    open my $fh, '<:raw', $path or return '';
    my $sha = Digest::SHA->new(256);
    $sha->addfile($fh);
    close $fh;
    return $sha->hexdigest;
}

# --- Fuzzy matching (shared logic) ---

sub resolve_blocks {
    my ($blocks_path, $config_path) = @_;

    my @files = map { my $b = fileparse($_, qr/\.key/i); $b } bsd_glob("$blocks_path/*.key");
    my @files_lower = map { lc } @files;

    open my $fh, '<', $config_path or die "Cannot open $config_path: $!";
    my @lines = grep { /\S/ } <$fh>;
    close $fh;
    chomp @lines;

    my @matched_names;
    my @inexact_matches;
    my $config_modified = 0;

    for my $raw_name (@lines) {
        my $base = $raw_name;
        $base =~ s/^\s+|\s+$//g;
        $base =~ s/\.key$//i;
        my $base_lower = lc $base;

        my $best_idx;
        my $best_score = -1;
        for my $i (0 .. $#files) {
            my $score = jaro_winkler($base_lower, $files_lower[$i]);
            if ($score > $best_score) {
                $best_score = $score;
                $best_idx = $i;
            }
        }
        next unless defined $best_idx;

        my $matched_base = $files[$best_idx];

        if ($base ne $matched_base) {
            push @inexact_matches, "'$base' -> '$matched_base'";
            $config_modified = 1;
        } elsif ($raw_name =~ s/^\s+|\s+$//gr ne $matched_base) {
            $config_modified = 1;
        }

        push @matched_names, $matched_base;
    }

    if ($config_modified) {
        open my $out, '>', $config_path or die "Cannot write $config_path: $!";
        print $out join("\n", @matched_names) . "\n";
        close $out;
    }

    return (\@matched_names, \@inexact_matches);
}

# --- Manifest I/O ---

sub manifest_path {
    my ($manifest_dir, $config_path) = @_;
    my ($config_name) = fileparse($config_path, qr/\.[^.]*/);
    return "$manifest_dir/$config_name.manifest";
}

sub read_manifest {
    my ($path) = @_;
    my %hashes;
    return %hashes unless -f $path;
    open my $fh, '<', $path or return %hashes;
    while (<$fh>) {
        chomp;
        if (/^(.+?)=(.+)$/) {
            $hashes{$1} = $2;
        }
    }
    close $fh;
    return %hashes;
}

sub write_manifest {
    my ($path, %hashes) = @_;
    my $dir = dirname($path);
    make_path($dir) unless -d $dir;
    open my $fh, '>', $path or die "Cannot write manifest $path: $!";
    # Write CONFIG first, then BLOCKs sorted
    if (exists $hashes{CONFIG}) {
        print $fh "CONFIG=$hashes{CONFIG}\n";
    }
    for my $key (sort grep { /^BLOCK:/ } keys %hashes) {
        print $fh "$key=$hashes{$key}\n";
    }
    close $fh;
}

sub compute_hashes {
    my ($blocks_path, $config_path, $matched_names_ref) = @_;
    my %hashes;
    $hashes{CONFIG} = hash_file($config_path);
    for my $name (@$matched_names_ref) {
        my $block_file = "$blocks_path/$name.key";
        $hashes{"BLOCK:$name"} = hash_file($block_file) if -f $block_file;
    }
    return %hashes;
}

sub is_stale {
    my ($manifest_dir, $blocks_path, $config_path, $matched_names_ref) = @_;
    my $mpath = manifest_path($manifest_dir, $config_path);
    return 1 unless -f $mpath;  # No manifest = stale

    my %old = read_manifest($mpath);
    my %current = compute_hashes($blocks_path, $config_path, $matched_names_ref);

    # Compare key counts
    return 1 if scalar(keys %old) != scalar(keys %current);

    # Compare each hash
    for my $key (keys %current) {
        return 1 unless exists $old{$key} && $old{$key} eq $current{$key};
    }
    return 0;
}

# --- Main ---

my $mode = '';
if (@ARGV >= 1 && $ARGV[0] =~ /^--/) {
    $mode = shift @ARGV;
}

if ($mode eq '--check') {
    # Usage: fuzzy_match.pl --check <manifest_dir> <blocks_path> <config_path>
    my ($manifest_dir, $blocks_path, $config_path) = @ARGV;
    my ($matched_names, $inexact_matches) = resolve_blocks($blocks_path, $config_path);

    my $stale = is_stale($manifest_dir, $blocks_path, $config_path, $matched_names);
    print "STATUS:" . ($stale ? "STALE" : "FRESH") . "\n";
    print "MATCHES:" . join('|', @$inexact_matches) . "\n";
    print "FILES:" . join('|', @$matched_names) . "\n";

} elsif ($mode eq '--write-manifest') {
    # Usage: fuzzy_match.pl --write-manifest <manifest_dir> <blocks_path> <config_path>
    my ($manifest_dir, $blocks_path, $config_path) = @ARGV;
    my ($matched_names, undef) = resolve_blocks($blocks_path, $config_path);

    my %hashes = compute_hashes($blocks_path, $config_path, $matched_names);
    my $mpath = manifest_path($manifest_dir, $config_path);
    write_manifest($mpath, %hashes);
    print "MANIFEST:$mpath\n";

} else {
    # Default mode (backward compatible): fuzzy_match.pl <blocks_path> <config_path>
    my $blocks_path = $ARGV[0];
    my $config_path = $ARGV[1];
    my ($matched_names, $inexact_matches) = resolve_blocks($blocks_path, $config_path);

    print "MATCHES:" . join('|', @$inexact_matches) . "\n";
    print "FILES:" . join('|', @$matched_names) . "\n";
}
