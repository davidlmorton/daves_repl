package ls;

use warnings;
use strict;

use Term::ANSIColor qw(colored);
use Set::Scalar;
use LayoutAndPrint "layout_and_print";
use ReplCore qw(
    ancestors
    class_name
    fullpath
    is_ur_class
    is_ur_object
    print_class_key
    print_header
    subs_info
);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    lineage
    ls
);

sub lineage {
    my $target = shift;
    my $verbose = shift;

    print_ancestry({class_name($target) => ancestors($target)},
        '  ', $verbose);
    return '';
}

sub print_ancestry {
    my $ancestors = shift;
    my $tab = shift;
    my $verbose = shift;

    if (ref $ancestors) {
        for my $key (keys %$ancestors) {
            if (not $verbose and ($key eq 'UR::Object' or $key eq 'UR::ModuleBase')) {
                # do nothing, because we don't want to see that stuff
            } else {
                printf("%s%s\n", $tab, format_ancestor($key, $verbose));
                print_ancestry($ancestors->{$key}, $tab . '  ', $verbose);
            }
        }
    } else {
        # do nothing, because it is a leaf node.
    }
}

sub format_ancestor {
    my $ancestor = shift;
    my $verbose = shift;

    my $class = colored($ancestor, 'green');
    if ($verbose) {
        return sprintf('%s %s', $class, fullpath($ancestor) || colored('cannot determine file', 'red'));
    } else {
        return $class
    }
}


sub ls {
    my $target = shift;
    my $verbose = shift;

    print_header($target);
    if (is_ur_object($target) or is_ur_class($target)) {
        ls_ur($target, $verbose);
    } else {
        die "Sorry, this command (ls) only works with UR objects and classes";
    }
    return ' ';
}

sub ls_ur {
    my $target = shift;
    my $verbose = shift;

    my $property_info = property_info($target);
    my $subs_info = subs_info($target);

    unless ($verbose) {
        remove_ur_object($property_info);
        remove_ur_object($subs_info);
    }
    my $class_symbols = class_symbols((values %$property_info, values %$subs_info));

    color_and_layout($property_info, $class_symbols, 'magenta');
    color_and_layout($subs_info, $class_symbols, 'cyan');
    print_class_key($class_symbols);
}

sub remove_ur_object {
    my $info = shift;

    for my $key (keys %$info) {
        if ($info->{$key} eq 'UR::Object' or
            $info->{$key} eq 'UR::ModuleBase') {
            delete $info->{$key};
        }
    }
    return;
}

sub property_info {
    my $target = shift;

    my %info;
    for my $property_meta ($target->__meta__->properties) {
        $info{$property_meta->property_name} = $property_meta->class_name;
    }
    return \%info;
}

sub class_symbols {
    my @classes = @_;

    my @possible_symbols = ('*', '**', '^', '^^', '#', '##', '&', '&&');

    my %symbols;
    for my $class (@classes) {
        my $symbol;
        unless (exists($symbols{$class})) {
            my $num_symbols = scalar(keys %symbols);
            $symbol = shift(@possible_symbols) ||
                    '*'x($num_symbols-5);
            $symbols{$class} = sprintf("%4s", $symbol);
        }
    }
    return \%symbols;
}

sub color_and_layout {
    my ($items, $class_symbols, $color) = @_;

    my @colored_items;
    for my $item (sort keys %$items) {
        my $class = $items->{$item};
        my $class_symbol = $class_symbols->{$class};
        my $formatted_item = sprintf("%s%s", $class_symbol, colored($item, $color));
        push @colored_items, $formatted_item;
    }
    layout_and_print([@colored_items], '  ');

    return;
}

1;
