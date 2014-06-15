package view;

use warnings;
use strict;

use Term::ANSIColor qw(colored);
use Term::ReadKey 'GetTerminalSize';
use Set::Scalar;
use LayoutAndPrint qw(layout_and_print width);
use Data::Dump qw(pp);
use ReplCore qw(
    is_ur_object
    print_class_key
    print_header
);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    view
);

my %COLORS = (
    'property' => 'magenta',
    'class' => 'green',
    'non-value' => 'cyan',
    'error' => 'red',
    'db' => 'blue',
);

sub view {
    my ($target, $verbose, $memory_safe) = @_;

    unless (is_ur_object($target) and $target->__meta__) {
        die sprintf("command (view) only works on UR objects (with __meta__)");
    }

    print_header($target);
    my ($properties, $class_symbols) = get_properties_and_class_symbols($target, $verbose, $memory_safe);
    print_view($target, $properties, $class_symbols, $verbose);

    return ' ';
}

sub get_properties_and_class_symbols {
    my $target = shift;
    my $verbose = shift;
    my $memory_safe = shift;

    my %properties;
    my @possible_symbols = ('*', '**', '^', '^^', '#', '##', '&', '&&');
    my %class_symbols = ($target->class => sprintf("%4s", ' '));

    for my $property_meta ($target->__meta__->properties) {
        my $name = $property_meta->property_name;
        my $class_name = $property_meta->class_name;

        unless (exists($class_symbols{$class_name})) {
            my $num_symbols = scalar(keys %class_symbols);
            my $symbol = shift(@possible_symbols) ||
                    '*'x$num_symbols;
            $class_symbols{$class_name} = sprintf("%4s", $symbol);
        }
        my $class_symbol = $class_symbols{$class_name};

        my $name_string;
        my $info_string = $verbose ? get_info($property_meta) : '';
        if ($info_string) {
            $name_string = sprintf("%s(%s)", colored($name, $COLORS{property}), $info_string);
        } else {
            $name_string = sprintf("%s", colored($name, $COLORS{property}));
        }

        $properties{$name} = sprintf("%s%s => %s", $class_symbol,
            $name_string,
            format_values($target, $name, $property_meta, $verbose, $memory_safe));
    }
    return \%properties, \%class_symbols;
}

sub get_info {
    my $meta = shift;
    my %info;

    if ($meta->default_value) {
        $info{default} = pp($meta->default_value);
    }

    if ($meta->via) {
        $info{via} = colored($meta->via, $COLORS{property});
    }

    my @strings;
    if ($meta->column_name) {
        push @strings, colored(uc $meta->column_name, $COLORS{db});
    }
    for my $key (keys %info) {
        push @strings, sprintf("%s=%s", $key, $info{$key});
    }

    return join(',', @strings);
}

sub format_values {
    my ($target, $accessor, $meta, $verbose, $memory_safe) = @_;

    if ($meta->is_calculated) {
        return colored('calculated', $COLORS{'non-value'});
    }

    if ($meta->is_many) {
        if ($memory_safe) {
            return colored('is_many', $COLORS{'non-value'});
        }
        my $values = eval {[$target->$accessor]};
        if ($@) {
            return colored('accessor error', $COLORS{error});
        } else {
            if ($verbose) {
                return sprintf("[%s]",
                    join(', ', map {format_single_value($_)} @$values));
            } elsif (scalar(@$values)) {
                my $ref = ref($values->[0]);
                my $plural = scalar(@$values) > 1 ? 's' : '';
                if ($ref) {
                    return sprintf("[%s %s object%s]",
                        scalar(@$values), colored($ref, $COLORS{class}), $plural);
                } else {
                    return sprintf("[%s value%s]", scalar(@$values), $plural);
                }
            } else {
                return "[]";
            }
        }
    } else {
        my $value = eval {$target->$accessor};
        if ($@) {
            return colored('accessor error', $COLORS{error});
        } else {
            return format_single_value($value);
        }
    }
}

sub format_single_value {
    my ($value) = @_;
    if (is_ur_object($value)) {
        return sprintf('%s->get(id => %s)', colored($value->class, $COLORS{class}),
            pp($value->id));
    } else {
        my $result = pp($value);
        if ($result eq 'undef') {
            return colored($result, $COLORS{'non-value'});
        } else {
            return $result;
        }
    }
}

sub print_view {
    my $target = shift;
    my %properties = %{(shift)};
    my %class_symbols = %{(shift)};
    my $verbose = shift;

    my @table_names = table_names($target);
    if ($verbose and scalar(@table_names)) {
        printf "Table(s): %s",
            sprintf("(%s) ", join(', ', map {colored(uc $_, $COLORS{db})} @table_names));
    }

    my (@long_entries, @short_entries);
    my $short_size = (GetTerminalSize())[0] / 3;
    for my $property_name (sort keys %properties) {
        if (width($properties{$property_name}) < $short_size) {
            push @short_entries, $properties{$property_name};
        } else {
            push @short_entries, format_short($properties{$property_name});
            push @long_entries, $properties{$property_name};
        }
    }
    if (@short_entries) {
        layout_and_print(\@short_entries, '  ');
    }
    for my $entry (@long_entries) {
        printf " %s\n", $entry;
    }

    delete $class_symbols{$target->class};
    print_class_key(\%class_symbols);
}

sub format_short {
    my $entry = shift;
    my ($name_part) = split(/\s=>\s/, $entry);
    return sprintf('%s => %s', $name_part, colored('see below', $COLORS{'non-value'}));
}

sub table_names {
    my $target = shift;

    my $names = Set::Scalar->new();
    for my $property ($target->__meta__->properties) {
        $names->insert(($property->table_and_column_name_for_property)[0]) if $property->column_name;
    }
    return $names->members;
}

