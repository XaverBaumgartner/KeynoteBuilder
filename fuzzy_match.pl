#!/usr/bin/perl
use strict;
use warnings;
use File::Glob ':bsd_glob';
use File::Basename;

# Jaro-Winkler similarity
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

    # Count matching characters
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

    # Count transpositions
    my $k = 0;
    for my $i (0 .. $n - 1) {
        next unless $s1_matched[$i];
        $k++ until $s2_matched[$k];
        $transpositions++ if substr($s1, $i, 1) ne substr($s2, $k, 1);
        $k++;
    }

    my $jaro = ($matches / $n + $matches / $m + ($matches - $transpositions / 2) / $matches) / 3;

    # Winkler prefix bonus (up to 4 chars)
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

my $blocks_path = $ARGV[0];
my $config_path = $ARGV[1];

# Read .key files from blocks folder
my @files = map { my $b = fileparse($_, qr/\.key/i); $b } bsd_glob("$blocks_path/*.key");
my @files_lower = map { lc } @files;

# Read config
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

    # Find best match (highest Jaro-Winkler similarity)
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

# Rewrite config.txt if anything changed
if ($config_modified) {
    open my $out, '>', $config_path or die "Cannot write $config_path: $!";
    print $out join("\n", @matched_names) . "\n";
    close $out;
}

# Structured output for AppleScript
print "MATCHES:" . join('|', @inexact_matches) . "\n"; # All filenames that had to be corrected
print "FILES:" . join('|', @matched_names) . "\n"; # All files in the presentation
