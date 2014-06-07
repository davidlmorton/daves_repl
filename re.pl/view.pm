package view;

use warnings;
use strict;

use Term::ANSIColor qw(colored);
use Term::ReadKey 'GetTerminalSize';
use Set::Scalar;
use LayoutAndPrint qw(layout_and_print width);
use Data::Dump qw(pp);

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
    my ($target, $verbose) = @_;

    unless (is_ur_object($target) and $target->__meta__) {
        die sprintf("command (view) only works on UR objects (with __meta__)");
    }

    my ($properties, $class_symbols) = get_properties_and_class_symbols($target, $verbose);
    print_view($target, $properties, $class_symbols, $verbose);

    return ' ';
}

sub is_ur_object {
    my $value = shift;
    if (ref($value) and UNIVERSAL::can($value, 'isa') and $value->isa('UR::Object')) {
        return 1;
    } else {
        return 0;
    }
}

sub get_properties_and_class_symbols {
    my $target = shift;
    my $verbose = shift;

    my %properties;
    my @possible_symbols = ('*', '**', '^', '^^', '#', '##', '&', '&&');
    my %class_symbols = ($target->class => '');

    for my $property_meta ($target->__meta__->properties) {
        my $name = $property_meta->property_name;
        my $class_name = $property_meta->class_name;

        my $class_symbol;
        if (exists($class_symbols{$class_name})) {
            $class_symbol = $class_symbols{$class_name};
        } else {
            my $num_symbols = scalar(keys %class_symbols);
            $class_symbol = shift(@possible_symbols) ||
                    '*'x$num_symbols;
            $class_symbols{$class_name} = $class_symbol;
        }

        my $name_string;
        my $info_string = $verbose ? get_info($property_meta) : '';
        if ($info_string) {
            $name_string = sprintf("%s(%s)", colored($name, $COLORS{property}), $info_string);
        } else {
            $name_string = sprintf("%s", colored($name, $COLORS{property}));
        }

        $properties{$name} = sprintf("%s%s => %s", $class_symbol,
            $name_string,
            format_values($target, $name, $property_meta, $verbose));
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
    my ($target, $accessor, $meta, $verbose) = @_;

    if ($meta->is_calculated) {
        return colored('calculated', $COLORS{'non-value'});
    }

    if ($meta->is_many) {
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
    printf("==== %s %s====\n", colored($target->class, $COLORS{class}),
        (scalar(@table_names) and $verbose) ?
            sprintf("(%s) ", join(', ', map {colored(uc $_, $COLORS{db})} @table_names)) : '');
    my (@long_entries, @short_entries);
    my $short_size = (GetTerminalSize())[0] / 3;
    for my $property_name (sort keys %properties) {
        if (width($properties{$property_name}) < $short_size) {
            push @short_entries, $properties{$property_name};
        } else {
            push @long_entries, $properties{$property_name};
        }
    }
    if (@short_entries) {
        layout_and_print(\@short_entries, '    ');
    }
    for my $entry (@long_entries) {
        printf "    %s\n", $entry;
    }
    for my $class_name (sort {$class_symbols{$a} cmp $class_symbols{$b}} keys %class_symbols) {
        if ($class_name ne $target->class) {
            printf "%s defined in %s\n", $class_symbols{$class_name},
            colored($class_name, $COLORS{class});
        }
    }
}

sub table_names {
    my $target = shift;

    my $names = Set::Scalar->new();
    for my $property ($target->__meta__->properties) {
        $names->insert(($property->table_and_column_name_for_property)[0]) if $property->column_name;
    }
    return $names->members;
}

