#!perl
use common::sense;

use Test::More;

eval {
    require Test::Kwalitee;
    Test::Kwalitee->import(tests => [qw(-use_strict)]);
};

plan skip_all => "Test::Kwalitee required for testing kwalitee" if $@;
