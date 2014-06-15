package ReplCore;

use warnings FATAL => 'all';
use strict;
no strict 'refs';

require Class::Inspector;
use Term::ANSIColor qw(colored);
use LayoutAndPrint "layout_and_print";
use IPC::System::Simple qw(capture);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    ancestors
    class_name
    fullpath
    is_ur_class
    is_ur_object
    parents
    print_class_key
    print_header
    subs
    subs_info
);

sub is_ur_object {
    my $value = shift;
    if (ref($value) and UNIVERSAL::can($value, 'isa') and $value->isa('UR::Object')) {
        return 1;
    } else {
        return 0;
    }
}

sub is_ur_class {
    my $value = shift;

    if (Class::Inspector->installed($value) and $value->isa('UR::Object')) {
        return 1;
    } elsif (UNIVERSAL::can($value, 'isa') and $value->isa('UR::Object')) {
        return 1;
    } else {
        return 0;
    }
}

sub ancestors {
    my $target = shift;

    my $class_name = class_name($target);
    my @parents = parents($target);

    if (scalar(@parents)) {
        my $tree = {};
        for my $parent (@parents) {
            $tree->{$parent} = ancestors($parent);
        }
        return $tree;
    } else {
        return 0;
    }
}

sub parents {
    my $target = shift;

    load($target);
    my @parents;
    if (ref $target) {
        return @{$target->class . '::ISA'};
    } else {
        return @{$target . '::ISA'};
    }
}

sub load {
    my $target = shift;

    if (ref($target) and Class::Inspector->installed(ref $target)) {
        return;
    } else {
        if (Class::Inspector->installed($target)) {
            if (not Class::Inspector->loaded($target)) {
                $target->can('anything');
            }
        } elsif (UNIVERSAL::can($target, 'isa')) {
            $target->can('anything');
        } else {
            die "Target ($target) is not an installed class or object";
        }
    }
}

sub class_name {
    my $target = shift;

    load($target);
    if (ref $target) {
        return ref $target;
    } else {
        return $target;
    }
}

sub subs_info {
    my $target = shift;
    my $info = shift || {};

    my $class_name = class_name($target);
    for my $sub (subs($target)) {
        $info->{$sub} = $class_name;
    }

    for my $parent (parents($target)) {
        subs_info($parent, $info);
    }
    return $info;
}

sub fullpath {
    my $target = shift;

    load($target);
    my $filename;
    if (ref $target) {
        $filename = Class::Inspector->filename(ref $target);
    } else {
        $filename = Class::Inspector->filename($target);
    }

    return $INC{$filename};
}

sub subs {
    my $target = shift;

    return subs_from_fullpath(fullpath($target));
}

sub subs_from_fullpath {
    my $fullpath = shift;
    return () unless $fullpath;

    my $grep_regex = '^sub\s[a-zA-Z_][0-9a-zA-Z_]*';
    my @lines = capture([0..1], "grep", '--perl-regex', $grep_regex, $fullpath);

    my @subs;
    for my $line (@lines) {
        if ($line =~ /^sub\s([a-zA-Z_][0-9a-zA-Z_]*)/) {
            push @subs, $1;
        }
    }
    return @subs;
}

sub print_class_key {
    my $class_symbols = shift;

    my @parts;
    for my $class (sort {strip($class_symbols->{$a}) cmp strip($class_symbols->{$b})} keys %$class_symbols) {
        my $symbol = $class_symbols->{$class};
        push @parts, sprintf "%s %s", $symbol, colored($class, 'green');
    }
    layout_and_print(\@parts, '');
}

sub strip {
    (my $s = shift) =~ s/^\s*//;
    return $s;
}

sub print_header {
    my $target = shift;

    printf "%s from %s\n", colored(class_name($target), 'green'), fullpath($target);
}


1;
