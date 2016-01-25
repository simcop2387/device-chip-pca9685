package Device::Chip::PCA9685;

use strict;
use warnings;

our $VERSION = 'v0.01';

use base qw/Device::Chip/;

use Time::HiRes q/usleep/;

my %REGS = (
    MODE1 => {addr => 0},
    MODE2 => {addr => 1},
    SUBADR1 => {addr => 2},
    SUBADR2 => {addr => 3},
    SUBADR3 => {addr => 4},
    ALLCALLADR => {addr => 5},
    ALL_CHAN_ON_L => {addr => 0xFA},
    ALL_CHAN_ON_H => {addr => 0xFB},
    ALL_CHAN_OFF_L => {addr => 0xFC},
    ALL_CHAN_OFF_H => {addr => 0xFD},
    PRE_SCALE => {addr => 0xFE},
    TEST_MODE => {addr => 0xFF},
);

for my $n (0..15) {
    $REGS{"CHAN${n}_ON_L"}  = {addr => 0x06 + $n * 4};
    $REGS{"CHAN${n}_ON_H"}  = {addr => 0x07 + $n * 4};
    $REGS{"CHAN${n}_OFF_L"} = {addr => 0x08 + $n * 4};
    $REGS{"CHAN${n}_OFF_H"} = {addr => 0x09 + $n * 4};
}

use utf8;

use constant PROTOCOL => "I2C";

sub _command {
    my $self = shift;
    my ($register, @bytes) = @_;
    
    my $regv = $REGS{$register}{addr};
    
    use Data::Dumper;
    print Dumper({reg => $register, bytes => \@bytes});
    
    $self->protocol->write(pack("C*", $regv, @bytes));
}

# All our registers are single 8 bit values.
sub _read_reg {
    my $self = shift;
    my ($register) = @_;
    
    my $regv = $REGS{$register}{addr};
    
    my ($value) = $self->protocol->write_then_read("\0", 1)->get;
    
    return unpack("C", $value);
}

sub I2C_options {my $self = shift; return (addr => 0x40, @_)}; # pass it through, but allow the address to change if passed in, should use a constructor instead

=head2 set_channel_value

    $chip->set_channel_value($channel, $time_on, $offset = 0)
    
Sets a channel PWM time based on a single value from 0-4095.  Starts the channel to turn on at COUNTER = 0, and off at $time_on.
C<$offset> lets you stagger the time that the channel comes on and off.  This lets you vary the times that channels go on and off 
to reduce noise effects and power supply issues from large loads all coming on at once.

C<$on_time> := 0; C<$off_time> := $time_on;

=cut

sub set_channel_value {
    my $self = shift;
    my ($chan, $time_on, $offset) = @_;
    $offset //= 0;
    
    # set the high parts first, we shouldn't ever have backtracking then

    if ($time_on < 0 || $time_on >= 4096) {
        $time_on = $time_on >= 4096 ? 4095 : 0;
        warn "Channel outside allowed value, clamping: $chan, $time_on\n";
    }

    $offset %= 4096; # wrap the offset around, that way you can increment it by any amount and have it work as expected
    $time_on = ($time_on + $offset) % 4096; # wrap it around based on the offset.
    
    $self->set_channel_full_value($chan, $offset, $time_on);
}

=head2 set_channel_full_value

    $chip->set_channel_full_value($channel, $on_time, $off_time)
    
Set a channel value, on and off time.  Lets you control the full on and off time based on the 12 bit counter on the device.

=cut

sub set_channel_full_value {
    my ($self, $chan, $on_t, $off_t) = @_;

    my ($on_h_t, $on_l_t)   = (($on_t & 0x0F00) >> 8,  ($on_t & 0xFF));
    my ($off_h_t, $off_l_t) = (($off_t & 0x0F00) >> 8, ($off_t & 0xFF));

    $self->_command("CHAN${chan}_ON_H", $on_h_t);
    $self->_command("CHAN${chan}_OFF_H", $off_h_t);
    $self->_command("CHAN${chan}_ON_L", $on_l_t);
    $self->_command("CHAN${chan}_OFF_L", $off_l_t);
}

=head2 set_channel_on

    $chip->set_channel_on($channel)
    
Set a channel to full on.  No off time at all.

=cut

sub set_channel_on {
    my ($self, $chan) = @_;
    
    $self->_command("CHAN${chan}_ON_H" => 0x10); # Set bit 4 of ON high, this is the bit that sets the channel to full on
    $self->_command("CHAN${chan}_ON_L" => 0x00);
    $self->_command("CHAN${chan}_OFF_H"=> 0x00);
    $self->_command("CHAN${chan}_OFF_L"=> 0x00);
}

=head2 set_channel_off

    $chip->set_channel_off($channel)
    
Set a channel to full off.  No on time at all.

=cut

sub set_channel_off {
    my ($self, $chan) = @_;
    
    $self->_command("CHAN${chan}_ON_H" => 0x00);
    $self->_command("CHAN${chan}_ON_L" => 0x00);
    $self->_command("CHAN${chan}_OFF_H"=> 0x10); # Set bit 4 of OFF high, this is the bit that sets the channel to full off
    $self->_command("CHAN${chan}_OFF_L"=> 0x00);
}

=head2 set_default_mode

    $chip->set_default_mode()
    
Reset the default mode back to the PCA9685.

=cut

sub set_default_mode {
    my $self = shift;
    # Sets all the mode registers to the chip defaults
    $self->_command(MODE1 => 0b0000_0001);
    $self->_command(MODE2 => 0b000_00100);
}

# =head2 enable
# 
#     $chip->enable()
#     
# Set the prescaler, frequency, and turn on the outputs
# 
# =cut
# 
# sub enable {
#     my $self = shift;
# 
#     
# }

=head2 set_frequency

    $chip->set_frequency()
    
Set the prescaler to the desired frequency for PWM.  Returns the real frequency due to rounding.

=cut

sub set_frequency {
    my $self = shift;
    my ($freq) = @_;
    use Data::Dumper;
    
    my $old_mode1 = $self->_read_reg("MODE1");
    my $new_mode1 = ($old_mode1 & 0x7f) | 0x10; # Set the chip to sleep, make sure reset is disabled while we do this to avoid noise/phase differences
    
    $self->_command(MODE1 => $new_mode1);
    
    my $divisor = int( ( 25000000 / ( 4096 * $freq ) ) + 0.5 ) - 1;
    if ($divisor < 3) { die "PCA9685 forces the scaler to be at least >= 3 (1526 Hz)." };
    if ($divisor > 255) { die "PCA9685 forces the scaler to be <= 255 (24Hz)." };
    
    $self->_command(PRE_SCALE => $divisor);
    $self->_command(MODE1 => $old_mode1);
    usleep(5000);
    $self->_command(MODE1 => $old_mode1 | 0x80);
    
    my $realfreq = 25000000 / (($divisor + 1)*(4096));
    
    return $realfreq;
}

1;