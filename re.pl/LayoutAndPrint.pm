package LayoutAndPrint;

use warnings;
use strict;

use Term::ReadKey 'GetTerminalSize';
use List::Util qw(max min sum);
use POSIX qw(strftime ceil);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    layout_and_print
);


sub layout_and_print {
    my ($items, $left_padding, $separator) = @_;
    my @items = @{$items};
    $left_padding = '    ' unless defined($left_padding);
    $separator = '   ' unless defined($separator);

    my @uncolored_items = map {color_strip($_)} @items;
    my @column_widths = determine_column_widths(\@uncolored_items, $left_padding, $separator);
    print_packed_items(\@items, \@column_widths, $left_padding, $separator);
    return " "; # so data dumper doesn't error out
}

# return the string with all color escape sequences removed
sub color_strip {
    my ($string) = @_;
    $string =~ s/\e\[[\d;]*[a-zA-Z]//g;
    return $string;
}

# return items packed into n groups
sub pack_items {
    my ($items, $n) = @_;
    my @items = @{$items};
    my $group_size = ceil(scalar(@items)/$n);
    my @groups;
    for (1..$n) {
        my @group;
        for (1..$group_size) {
            my $item = shift(@items);
            if(defined $item) {
                push(@group, $item);
            }
        }
        push(@groups, \@group) if scalar(@group);
    }
    return @groups;
}

sub print_packed_items {
    my ($items, $column_widths, $left_padding, $separator) = @_;
    my @column_widths = @{$column_widths};

    my $num_columns = scalar(@column_widths);
    my @packed_items = pack_items($items, $num_columns);

    my @first_column = @{$packed_items[0]};
    my $max_rows = scalar(@first_column);
    for my $row (0..$max_rows) {
        for(my $col=0; $col<$num_columns; $col++) {
            my $width = $column_widths[$col];
            my @column = @{$packed_items[$col]};
            my $item = $column[$row];
            if(defined($item)) {
                print($left_padding) if $col == 0;
                printf("%s", left_justify($item, $width));
                print($separator) unless $col == $num_columns - 1;
            }
        }
        print "\n" unless($row == $max_rows);
    }
    return;
}

sub left_justify {
    my ($string, $field_width) = @_;
    my $uncolored_string = color_strip($string);
    my $num_spaces_needed = $field_width - length($uncolored_string);
    if($num_spaces_needed > 0) {
        return $string . ' 'x$num_spaces_needed;
    } else {
        return $string;
    }
}

# return column widths needed to display a list of items most
# efficiently on the screen
sub determine_column_widths {
    my ($items, $left_padding, $separator) = @_;
    my @items = @{$items};

    my ($screen_width) = GetTerminalSize();
    $screen_width -= length($left_padding);

    my $max_num_columns = ceil($screen_width/2);
    $max_num_columns = min(($max_num_columns, scalar(@items)));

    my @item_lengths = map {length color_strip($_)} @items;
    for(my $i=$max_num_columns; $i>0; $i--) {
        my @packed_item_lengths = pack_items(\@item_lengths, $i);
        my @column_widths = _column_widths(@packed_item_lengths);
        my $num_columns = scalar(@column_widths);
        $i = $num_columns; # drop down to however many columns we packed into.
        my $num_spaces = ($num_columns - 1) * length($separator);
        my $total_width = sum(@column_widths) + $num_spaces;
        if($total_width <= $screen_width) {
            return @column_widths;
        }
    }
}

# word lengths are stored in @columns like:
#   ([1,3],[4,5],[3])
#   returns (3, 5, 3)
sub _column_widths {
    my @columns = @_;
    my @widths;
    for my $column (@columns) {
        my @rows = @{$column};
        push(@widths, max(@rows));
    }
    return @widths;
}
