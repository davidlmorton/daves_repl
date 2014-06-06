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

# print information
sub view {
    my ($target) = @_;

    unless (is_ur_object($target)) {
        die sprintf("command (view) only works on UR objects");
    }

    my ($properties, $class_symbols) = get_properties_and_class_symbols($target);
    print_view($target, $properties, $class_symbols);

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

    my %properties;
    my @possible_symbols = ('*', '**', '#', '##', '&', '&&', '^', '^^');
    my %class_symbols = ($target->class => '');

    for my $name ($target->property_names) {
        my $meta = $target->__meta__->property_meta_for_name($name);
        my $class_name = $meta->class_name;

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
        if ($meta->default_value) {
            $name_string = sprintf("%s%s(default=%s)" , $class_symbol, $name,
                pp($meta->default_value));
        } else {
            $name_string = $class_symbol . $name;
        }

        $properties{$name} = sprintf("%s = %s", colored($name_string, 'cyan'),
            format_values($target, $name, $meta));
    }
    return \%properties, \%class_symbols;
}

sub format_values {
    my ($target, $accessor, $meta) = @_;

    if ($meta->is_calculated) {
        return colored('is calculated', 'magenta');
    }

    if ($meta->is_many) {
        my $values = eval {[$target->$accessor]};
        if ($@) {
            return colored('accessor error', 'red');
        } else {
            return sprintf("[%s]",
                join(', ', map {format_single_value($_)} @$values));
        }
    } else {
        my $value = eval {$target->$accessor};
        if ($@) {
            return colored('accessor error', 'red');
        } else {
            return format_single_value($value);
        }
    }
}

sub format_single_value {
    my ($value) = @_;
    if (is_ur_object($value)) {
        return sprintf('%s->get(id => %s)', $value->class,
            pp($value->id));
    } else {
        return pp($value);
    }
}

sub print_view {
    my $target = shift;
    my %properties = %{(shift)};
    my %class_symbols = %{(shift)};

    printf("==== %s ====\n", colored($target->class, 'green'));
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
            colored($class_name, 'green');
        }
    }
}

