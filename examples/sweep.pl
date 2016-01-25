#!/usr/bin/env perl

use strict;
use warnings;

use lib './lib';

use Device::Chip::PCA9685;
use Device::Chip::Adapter;

my $adapter = Device::Chip::Adapter->new_from_description("LinuxKernel");

my $chip = Device::Chip::PCA9685->new();
# This is the i2c bus on an RPI 2 B+
$chip->mount($adapter, bus => '/dev/i2c-1')->get;

$chip->set_frequency(400); # 400 Hz

for (0..4095) {
    $chip->set_channel_value(0, $_);
}