package ls;

use warnings;
use strict;
no strict 'refs';

use Term::ANSIColor qw(colored);
require Class::Inspector;
use PadWalker 'peek_my';
use Set::Scalar;
use LayoutAndPrint "layout_and_print";

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    ls
    get_local_variables
);

# return the names and types of local variables
sub get_local_variables {
    my ($level) = @_;
    $level = 1 unless(defined($level));

    my $p = peek_my($level);
    my %p = %{$p};
    my @names = keys %p;
    my @values = values %p;
    my @types = map {ref($_)} @values;

    return \@names, \@types;
}

# print information
sub ls{
    my ($target) = @_;

    if(defined($target)) {
        my $target_ref = ref($target);
        if($target_ref) {
            if(Class::Inspector->installed($target_ref) or
               Class::Inspector->loaded($target_ref)) {
                ls_class($target_ref);
            } elsif($target_ref eq 'HASH') {
                ls_hash($target);
            } else {
                die sprintf("ls cannot interrogate '%s'\n", $target_ref);
            }
        } else {
            if(Class::Inspector->installed($target) or
               Class::Inspector->loaded($target)) {
                ls_class($target);
            } else {
                die sprintf("ls cannot interrogate '%s'\n", $target);
            }

        }
    } else {
        ls_local_variables();
    }
    return ' ';
}

# print information about local variables
sub ls_local_variables {
    my ($names, $types) = get_local_variables(3);

    my @colors = colorize_variable_names(
            [qw(ARRAY HASH SCALAR REF other)],
            [qw(ARRAY HASH SCALAR REF other)]);
    printf("Local variables: (%s)\n", join(', ', @colors));
    my @colored_names = colorize_variable_names($names, $types);
    my @sorted_names = sort(@colored_names);
    layout_and_print(\@sorted_names, '    ');
}

# print information about a hash reference
sub ls_hash {
    my ($target) = @_;

    my ($keys, $types) = get_hashref_info($target);

    my @colors = colorize_variable_names(
            [qw(ARRAY HASH SCALAR REF other)],
            [qw(ARRAY HASH SCALAR REF other)]);
    printf("A hash reference with keys: (%s)\n", join(', ', @colors));
    my @colored_keys = colorize_variable_names($keys, $types);
    my @sorted_keys = sort(@colored_keys);
    layout_and_print(\@sorted_keys, '    ');
}

sub get_hashref_info {
    my ($hashref) = @_;

    my @keys = keys %{$hashref};
    my @types = map {ref($hashref->{$_})} @keys;
    return \@keys, \@types;
}

# print information about a class or object
sub ls_class {
    my ($target, $is_continuation) = @_;

    my %info = get_method_and_property_info($target);
    layout_and_print_ls_info($target, \%info,
            $is_continuation);

    # continuation
    unless($is_continuation) {
        my @parents = get_class_parents_recursively($target);
        # only show each parent once
        my $parents_set = Set::Scalar->new(@parents);
        for my $parent (@parents) {
            if($parents_set->has($parent)) {
                $parents_set->delete($parent);
                ls_class($parent, 1)
            }
        }
    }
}

sub layout_and_print_ls_info {
    my ($target_class, $info, $is_continuation) = @_;
    my %info = %{$info};

    # header
    if($is_continuation) {
        printf("and defined in %s:\n",  colored($target_class, 'magenta'));
    } else {
        printf("%s and %s defined in %s: (%s if overwrites inherited definition)\n",
                colored('Methods', 'cyan'),
                colored('properties', 'green'),
                colored($target_class, 'magenta'),
                colored('bold', 'bold'));
    }

    # body
    my @colored_names = map {colored($_, 'cyan')} sort($info{new_methods}->members);
    @colored_names = (@colored_names,
            map {colored($_, 'cyan bold')} sort($info{overwritten_methods}->members));
    @colored_names = (@colored_names,
            map {colored($_, 'green')} sort($info{new_properties}->members));
    @colored_names = (@colored_names,
            map {colored($_, 'bold green')} sort($info{overwritten_properties}->members));
    layout_and_print(\@colored_names, '   ');
}

sub get_method_and_property_info {
    my ($target) = @_;

    my %result;
    # get this class/objects method and property names
    my @tmn = get_class_methods($target);
    my @tpn = get_property_names($target);
    $result{this_method_names} = \@tmn;
    $result{this_property_names} = \@tpn;

    # get parents/grandparents... method and property names
    my @parent_method_names;
    my @parent_property_names;
    for my $parent (get_class_parents($target)) {
        @parent_method_names = (@parent_method_names,
                get_class_methods_recursively($parent));
        @parent_property_names = (@parent_property_names,
                get_property_names_recursively($parent));
    }
    $result{parent_method_names} = \@parent_method_names;
    $result{parent_property_names} = \@parent_property_names;

    for my $key (keys %result) {
        $result{sprintf("%s_set", $key)} = Set::Scalar->new(@{$result{$key}});
    }

    my $tm = $result{this_method_names_set};
    my $pm = $result{parent_method_names_set};
    my $tp = $result{this_property_names_set};
    my $pp = $result{parent_property_names_set};

    if($target->can('__meta__')) {
        # Since UR properties automatically create a method for get/set, remove those from the
        # methods sets.
        $tm = $tm - $tp - $pp;
        $pm = $pm - $tp - $pp;
    } else {
        $tp = $tp - $tm - $pm;
        $pp = $pp - $tm - $pm;
    }

    $result{new_methods} = $tm - $pm;
    $result{new_properties} = $tp - $pp;

    $result{overwritten_methods} = $tm->intersection($pm);
    $result{overwritten_properties} = $tp->intersection($pp);

    $result{inherited_methods} = $pm - $tm;
    $result{inherited_properties} = $pp - $tp;

    return %result;
}

sub colorize_variable_names {
    my ($names, $types) = @_;
    my @names = @{$names};
    my @types = @{$types};

    my %colors = (
        'ARRAY' => 'green',
        'HASH' => 'magenta',
        'SCALAR' => 'cyan',
        'REF' => 'red',
        'other' => 'blue',
    );
    my @colored_variable_names;
    my $end = scalar(@names) - 1;
    for my $i (0..$end) {
        my $name = $names[$i];
        my $type = $types[$i];
        my $color = defined($colors{$type}) ? $colors{$type} : $colors{other};
        push(@colored_variable_names, colored($name, $color));
    }
    return @colored_variable_names;
}

sub get_class_methods {
    my ($target) = @_;
    if(Class::Inspector->installed($target) or
       Class::Inspector->loaded($target)) {
        my $function_names = Class::Inspector->methods($target);
        my @function_names = @{$function_names};
        my $method_names = Class::Inspector->functions($target);
        my @method_names = @{$method_names};
        my @names = (@function_names, @method_names);
        return @names;
    } else {
        my @empty;
        return @empty;
    }
}

sub get_class_methods_recursively {
    my ($target) = @_;

    my @function_names = get_class_methods($target);
    for my $parent (get_class_parents($target)) {
        @function_names = (@function_names, get_class_methods_recursively($parent));
    }
    return @function_names;
}

sub get_property_names {
    my ($target) = @_;
    if($target->can('__meta__')) {
        my @property_names;
        for my $prop ($target->__meta__->properties) {
            if($prop->{class_name} eq $target->class) {
                push(@property_names, $prop->{property_name});
            }
        }
        return @property_names;
    } elsif(Class::Inspector->installed($target) or
            Class::Inspector->loaded($target)) {
        my @property_names = keys %{$target . "::"};
        return @property_names;
    } else {
        my @empty;
        return @empty;
    }
}

sub get_property_names_recursively {
    my ($target) = @_;

    my @property_names = get_property_names($target);
    for my $parent (get_class_parents($target)) {
        @property_names = (@property_names, get_property_names_recursively($parent));
    }
    return @property_names;
}

sub get_class_parents {
    my ($target) = @_;

    return @{$target . '::ISA'};
}

sub get_class_parents_recursively {
    my ($target) = @_;
    my @parents = get_class_parents($target);
    for my $parent (get_class_parents($target)) {
        @parents = (@parents, get_class_parents_recursively($parent));
    }
    return @parents;
}


