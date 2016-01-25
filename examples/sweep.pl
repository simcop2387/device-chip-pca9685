#!/usr/bin/env perl

use strict;
use warnings;

use lib './lib';

use Device::Chip::PCA9685;
use Device::Chip::Adapter;

my $adapter = Device::Chip::Adapter->new_from_description("LinuxKernel");
my $proto = $adapter->make_protocol("I2C");

my $chip = Device::Chip::PCA9685->new();
$chip->mount($adapter, bus => '/dev/i2c-1')->get;

#$chip->enable();
$chip->set_frequency(400); # 400 Hz

for (0..4095) {
print "...\n";
$chip->set_channel_value(0, $_);
}