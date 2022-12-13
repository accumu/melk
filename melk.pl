#!/usr/bin/perl
# melk, a dns thingie
#
#  Copyright (C) 2001-2022 Mattias Wadenstein et al.
#  https://github.com/accumu/melk
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU Affero General Public License as published
#  by the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Affero General Public License for more details.
#
#  You should have received a copy of the GNU Affero General Public License
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.


use strict;
use warnings;

use File::Temp qw /tempfile/;

my $verbose = $ENV{DEBUG}?1:0;
my $dryrun = 0;
my $cmd = $0 . " " . join(" ", @ARGV);
my $now = localtime;
my $infohdr = "; *********************************************************
; * Warning! Do NOT edit by hand! 
; * This file was automically generated with the command
; * $cmd
; * on $now
; *********************************************************\n\n";
my @tmpfiles;

$SIG{__DIE__}  = sub {

	return unless @tmpfiles;

	unless($ENV{DEBUG}) {
		print "Removing generated temporary files\n" if $verbose;
		unlink @tmpfiles;
	}
	else {
		print "Leaving temporary files:\n", join("\n", @tmpfiles), "\n";
	}
};

sub mywarn {
	print "\e[31m".join("",@_)."\e[0m";
}

if($ARGV[0] eq '-v') {
    $verbose = 1;
    shift @ARGV;
}

if($ARGV[0] eq '-n') {
    $dryrun = 1;
    shift @ARGV;
}

if ($#ARGV <3 or $#ARGV>5) {
	print("Usage: $0 [-v] [-n] <source file> <mx> <domain> <network> [<v6network>] [<subnet>]\n");
	exit(0);
}

my $inf = shift @ARGV;
my $mx = shift @ARGV;
my $zone = shift @ARGV;
my $ipnet = shift @ARGV;
my $ipv6net = shift @ARGV;
my $subnet = shift @ARGV;
my %hostip = ();
my %iphost = ();
my %dov4 = ();
my %dov6 = ();
my %dhcpdata = ();
my %dhcp6data = ();
my %ethersdata = ();
my $dhcpfilename = undef;
my $dhcp6filename = undef;
my $ethersfilename = undef;
my $reve6filename = undef;
my $ipv6prefix = undef;
my %dhcpgroups = (default => 1);
my %ethersfound = ();
my %sshfp = ();

if (defined $subnet) {
    $subnet = ".$subnet";
} else {
    $subnet = "";
}

if(defined $ipv6net && $ipv6net eq '-') {
    $ipv6net = undef;
}

# Make a suffix based on infile, needed in particular for the v6 reverse
# case for a v6 network spanning multiple v4 networks

my $infsuffix = $inf;
$infsuffix =~ s/.*\///g;
$infsuffix =~ s/.melk//g;

# If there is something trailing :: in the v6 net, let that be a prefix
# for the host part, not the network name.

if(defined $ipv6net) {
    ($ipv6net,$ipv6prefix) = split /::/,$ipv6net;
    $ipv6net .= "::";
}

# Only do dhcp if there is a "dhcp" directory (or symlink to directory)
$dhcpfilename = "dhcp/dhcp-$zone-$ipnet$subnet-$infsuffix" if -d "dhcp"; 
$ethersfilename = "ethers/ethers-$zone-$ipnet$subnet-$infsuffix" if -d "ethers"; 
open(my $INFILE, $inf) or die "E3275 can't open infile $inf: $!";
print "I5601 Opened infile $inf\n" if $verbose;

my $forwfilename = "$zone/forw-$zone-$ipnet$subnet-$infsuffix";
my $revefilename = "$ipnet/rev-$ipnet$subnet-$zone-$infsuffix";

# Must create directories even in dry-run mode since we dump output to
# temporary files.
if (! -d "$ipnet") {
    mkdir($ipnet) or die "mkdir $ipnet: $!";
    print "Created directory '$ipnet'\n" if $verbose;
}

# And if we have an sshfp file, use that for SSHFP records
my $sshfpfilename = "$zone/sshfp.list";


if(defined $ipv6net) {
    $reve6filename = "$ipv6net/rev-$ipv6net-$zone-$infsuffix";
    $reve6filename =~ s/://g;

    my $ipv6dir = $ipv6net;
    $ipv6dir =~ s/://g;
    if (! -d "$ipv6dir") {
	mkdir($ipv6dir) or die "mkdir $ipv6dir: $!";
	print "Created directory '$ipv6dir'\n" if $verbose;
    }

    $dhcp6filename = "dhcp/dhcp-$zone-$ipv6net$infsuffix" if -d "dhcp"; 
    $dhcp6filename =~ s/://g;
}

my($FORVFILE, $forwfiletmp) = tempfile("$forwfilename.XXXXXX");
push @tmpfiles, $forwfiletmp;
my($REVEFILE, $revefiletmp) = tempfile("$revefilename.XXXXXX");
push @tmpfiles, $revefiletmp;
if($verbose) {
        print "I5602 Opened forw $forwfiletmp\n";
        print "I5603 Opened reve $revefiletmp\n";
}

if(open(my $SSHFPFILE, "$sshfpfilename")) {
    print "I5606 Opened sshfp $sshfpfilename\n" if $verbose;
    while(my $sline = <$SSHFPFILE>) {
          chomp $sline;
          my ($shost,$srest) = split(/ /, $sline, 2);
          my (undef,undef,$salgo,$sfptype,undef) = split(/ /, $srest);
          $sshfp{$shost}{$salgo}{$sfptype} = $srest;

          if($verbose) {
              print "I5609 found sshfp for | " . $shost . ' ' . $salgo . ' ' . $sfptype . " | with value of | " . $srest . " |\n";
          }
    }
} else {
    print "W5606 Can't open $sshfpfilename: $!\n" if $verbose;
}

my ($REVE6FILE, $reve6filetmp);
if($reve6filename) {
    ($REVE6FILE, $reve6filetmp) = tempfile("$reve6filename.XXXXXX");
    push @tmpfiles, $reve6filetmp;

    print "I5605 Opened reve6 $reve6filetmp\n" if $verbose;
}


#my ($DHCPFILE, $dhcpfiletmp);
#if($dhcpfilename) {
#    ($DHCPFILE, $dhcpfiletmp) = tempfile("$dhcpfilename.XXXXXX");
#    push @tmpfiles, $dhcpfiletmp;
#
#    print "I5604 Opened dhcp $dhcpfiletmp\n" if $verbose;
#}


sub forw { print $FORVFILE @_; }

sub reve { print $REVEFILE @_; }

sub reve6 { print $REVE6FILE @_; }

sub ethers($$) {
	my ($group,$data) = @_;

	$ethersdata{$group} .= $data;
}
sub dhcp($$) {
	my ($group,$data) = @_;

	$dhcpdata{$group} .= $data;
}
sub dhcp6($$) {
	my ($group,$data) = @_;

	$dhcp6data{$group} .= $data;
}

sub sethostip {
	my ($ip, @hosts) = @_;
	my $host;
	if (defined $hostip{$hosts[0]}) {
		mywarn "W3164 rad $.: host $hosts[0] har redan en ip=$ip\n";
	}
	if (defined $iphost{$ip}) {
		mywarn "W3113 rad $.: ip $ip har redan en host (".$iphost{$ip}.")\n";
	}
	foreach $host (@hosts) {
		$hostip{$host} = $ip;
	}
	$iphost{$ip} = $hosts[0];
}

sub hostip {
	my ($host) = shift;
	if (!defined $hostip{$host}) {
		die "E7664 \@$.:AIEIH, den hosten ($host) har ingen ip juh";
	}
	return $hostip{$host};
}

sub revip {
	my $ip = shift;
	my (@n, $rev);
	@n = split /\./, $ip;
	$rev = join(".", reverse(@n));
	return $rev;
}


# assumes 64-bit host part and at most 4 octets of $ip
sub rev4ip6 {
	my $ip = shift;
	my $prefix = shift;
	my (@n, $rev, $sub);
        @n = (0,0,0,0);
        if($prefix) {
                push @n, split(/:/, $prefix);
        }
        push @n, split(/\./,$ip);

        splice(@n,0,($#n-3));
        $sub="";
        for (@n) {
                 $sub .= sprintf "%04s", $_;
        }
        $rev=join ".",reverse(split //,$sub);
        return $rev;
}

sub makev6 {
    my ($ipnet,$prefix,$ip) = @_;
    if ($prefix) {
        $prefix .= ':';
    } else {
        $prefix="";
    }
    $ip = join(":",map(sprintf("%04u",$_),split /\./,$ip));
    $ip = $ipnet . $prefix . $ip;
    return $ip;
}

sub ethertov6 {
    my ($ether) = @_;
    my @eth = split(/[:-]/, lc $ether);
    for (@eth) {
            if ($_ !~ /^[a-f0-9]{1,2}$/i) {
                    die "Malformed ether address ($_ out of $ether)";
            }
    }
    $eth[0] = sprintf("%x",hex($eth[0]) ^ 0x2);# Toggle globally unique bit
    my $ret = sprintf "%s%s:%sff:fe%s:%s%s",
                $eth[0],$eth[1],$eth[2],$eth[3],$eth[4],$eth[5];
    $ret =~ s/:0+([0-9]+)/:$1/g;
    return $ret;

}
sub revip6 {
        my ($ipnet, $ip) = @_;
        $ip =~ s/^\Q$ipnet\E//;
        #print "[$ip]";
        my @ips = split(/:/, $ip);
        my $sub = "";
        for (@ips) {
                $sub .= sprintf "%04s", $_;
        }
        return join ".",reverse(split //,$sub);
}

sub cleanv6($) {
	my $ip = shift;
	my @a = split(/:/,$ip);
	#print "num=$#a\n";
	if ($#a == 8) {
		$ip =~ s/::/:/;
	}
	return $ip;
}

sub ipdata {
	my ($ip, @hosts) = @_;
	my ($host, $firsthost , $revip, $ip6, $ether);
	&sethostip($ip, @hosts);
	$firsthost = shift @hosts;
        $dov6{$ip} = 'v4' if defined $ipv6net;
        $dov4{$ip} = 1;
        my $dhcpoptions = '';
        my $dhcp6options = '';
	my $dhcpgroup = 'default';
	foreach $host (@hosts) {
# Hosts containing ":" are not hosts, but mac addresses for dhcp
	    if ($host =~ /v6=(ether|eth|\S+)/) {
		$dov6{$ip} = $1;
	    } elsif($host =~ /hpbootfile=(\S+)/) {
		$dhcpoptions = qq{    option hpbootfile "hpfiles/$1.cfg";\n};
	    } elsif ($host =~ /dhcp=(\S+)/) {
		if (!defined $dhcpgroups{$1}) {
		    print "Trying to use dhcp group [$1] which is not among the defined groups [";
		    print join("/",sort keys %dhcpgroups)."]\n";
		    die "";
		}
		$dhcpgroup = $1;
	    } elsif($host =~ /^-(.)$/) {
		$dov6{$ip} = 0 if $1 == '4';
		$dov4{$ip} = 0 if $1 == '6';
	    } elsif($dhcpfilename && $host =~ /[:]/) {
		$ether = $host;
		$ether =~ s/-/:/g;
	    } else {
		&forw("$host			CNAME	$firsthost\n");
	    }
	}
	if (defined $ether) {
		if (defined $ethersfound{lc($ether)}) {
			die "E9876 \@$.: Mac address $ether already existing for ".$ethersfound{lc($ether)};
		}
		$ethersfound{lc($ether)} = $firsthost;
	}
	if ($dhcpfilename && defined $ether) {
		&ethers($dhcpgroup,"$ether $firsthost\n");
		&dhcp($dhcpgroup,"host $firsthost.$zone-$ipnet {\n");
		&dhcp($dhcpgroup,"    option host-name \"$firsthost.$zone\";\n");
		&dhcp($dhcpgroup,"    hardware ethernet $ether;\n");
		&dhcp($dhcpgroup,"    fixed-address $firsthost.$zone; # $ipnet.$ip\n");
		&dhcp($dhcpgroup,$dhcpoptions);
		&dhcp($dhcpgroup,"}\n");
	}
	#TODO: Move into AAAA handling part below to use same ipv6 address as dns
	if ($dhcp6filename && defined $ether) {
                my $ipv6netNocol = $ipv6net;
                $ipv6netNocol =~ s/://g;
		&dhcp6($dhcpgroup,"host $firsthost.$zone-$ipv6netNocol {\n");
		&dhcp6($dhcpgroup,"    option host-name \"$firsthost.$zone\";\n");
		&dhcp6($dhcpgroup,"    hardware ethernet $ether;\n");
		&dhcp6($dhcpgroup,"    fixed-address6 $ipv6net$ip;\n");
		&dhcp6($dhcpgroup,$dhcp6options);
		&dhcp6($dhcpgroup,"}\n");
        }
        if($dov4{$ip}) {
            $revip = &revip($ip);
            &reve("$revip			PTR	$firsthost.$zone.\n");
            &forw("$firsthost			A	$ipnet.$ip\n");
        }
        if($dov6{$ip}) {
            if ($dov6{$ip} eq 'ether' or $dov6{$ip} eq 'eth') {
		#print "v6=ether ($ipv6net + $ip)\n";
                    if (!defined $ether) {
			die "v6=ether specified for host $ip/$firsthost, but no ether available";
                    }
		    $ip6=$ipv6net.&ethertov6($ether);
                    $ip6 = cleanv6($ip6);
		#print "\$ip6=$ip6\n";
		    &forw("$firsthost			AAAA    $ip6\n");
		    $revip = &revip6($ipv6net,&ethertov6($ether));
		    &reve6("$revip			PTR	$firsthost.$zone.\n");
            } elsif ($dov6{$ip} eq 'v4') {
		#print "v6=v4 ($ip)\n";
		    $ip6=&makev6($ipv6net,$ipv6prefix,$ip);
                    $ip6 = cleanv6($ip6);
		    &forw("$firsthost			AAAA    $ip6\n");
		    $revip = &rev4ip6($ip,$ipv6prefix);
		    &reve6("$revip			PTR	$firsthost.$zone.\n");
            } else {
		    #print "v6=spec ($ip -> $dov6{$ip})\n";
                    $ip6 = cleanv6($ip6);
		    &forw("$firsthost			AAAA	$dov6{$ip}\n");
		    $revip = &revip6($ipv6net,$dov6{$ip});
		    &reve6("$revip			PTR	$firsthost.$zone.\n");
                    
            }
        }
        
	if (defined($sshfp{$firsthost})) {
	    foreach my $salgo (sort keys %{$sshfp{$firsthost}}) {
		foreach my $sftptype (sort keys %{$sshfp{$firsthost}{$salgo}}) {
		    &forw("                            $sshfp{$firsthost}{$salgo}{$sftptype}\n");
		}
	    }
	}

	&forw("				MX 0 $mx\n");
}

sub cname {
    my ($dest, @hosts) = @_;
    my ($host);
    foreach $host (@hosts) {
        &forw("$host    CNAME   $dest\n");
    }
}

sub multiname {
	my ($mname, $ttl, @hosts) = @_;
	my ($ip, $host,$ip6);
	foreach $host (@hosts) {
		$ip = &hostip($host);
                if($dov4{$ip}) {
		        &forw("$mname	$ttl		A	$ipnet.$ip	; $host\n");
                } 
                if($dov6{$ip}) {
                    $ip6=&makev6($ipv6net,$ipv6prefix,$ip);
		    &forw("$mname	$ttl		AAAA	$ip6	; $host\n");
                } 
		$mname = "	";
	}
	&forw("				MX 0 $mx\n");
}

my ($line, $ip, $hosts, $cname, @hosts, $mname, $ttl);
&forw($infohdr);
&reve($infohdr);

while ($line = <$INFILE>) {
	next if ($line =~ /^\s*\#/); # COMMENTS (typ RCS headers...)
	if ($line =~ /^DHCPGROUPS=(.*)/) {
		my @groups = split(/\s+/,$1);
		%dhcpgroups = (%dhcpgroups,map { $_ => 1 } @groups);
	} elsif ($line =~ /^\|/) { # REVE+FORV
		$line =~ s/^\| ?//;
		&reve($line);
		&reve6($line) if $reve6filename;
		&forw($line);
	} elsif ($line =~ /^</) { # REVE
		$line =~ s/^< ?//;
		&reve($line);
	} elsif ($line =~ /^\&/) { # REVE6
		$line =~ s/^\& ?//;
		&reve6($line);
	} elsif ($line =~ /^>/) { # FORV
		$line =~ s/^> ?//;
		&forw($line);
	} elsif ($line =~ /^\*/) { # CNAMEs
		($hosts) = ($line =~ /^\* ?([a-zA-Z][\s.0-9a-zA-Z-]*)/);
		($cname, @hosts) = split(/\s+/, $hosts);
		&cname($cname, @hosts);
	} elsif ($line =~ /^;/) {
		&forw($line);
		&reve($line);
		&reve6($line) if $reve6filename;
	} elsif ($line =~ /^\s*$/) { # BLANK lines
		&forw("\n");
		&reve("\n");
		&reve6($line) if $reve6filename;
	} elsif ($line =~ /^\+/) { # ADD RR
		$line =~ s/^\+ ?/			/;
		&forw($line);
	} elsif ($line =~ /^[0-9][0-9.;]*[ \t0-9a-zA-Z:.=-]*(;.*)?$/) { # IPDATA
		$line =~ s/;.*//; # strip comment
		($ip, $hosts) = ($line =~ /([0-9.]+)\s+(.*)/);
		@hosts = split(/\s+/, $hosts);
		if ($#hosts == -1) {
			die "E2161 \@$.:Ey! ensam IP på rad $.";
		}
		&ipdata($ip, @hosts);
	} elsif ($line =~ /^[a-zA-Z][0-9a-zA-Z-]*(?:\(([0-9]+)\))?[ \t0-9;.a-zA-Z-]*$(;.*)?/) { # MULTINAME
		$ttl = $1 || "";
		$line =~ s/;.*//; # strip comment
		$line =~ s/\([0-9]+\)//; # remove ttl
		($mname, @hosts) = split(/\s+/, $line);
		if ($#hosts == -1) {
			die "E2641 \@$.: Ey! ensam host på rad $.";
		}
		&multiname($mname, $ttl,  @hosts);
	} elsif ($line =~ /^\@(?:\(([0-9]+)\))?[ \t0-9;.a-zA-Z-]*$(;.*)?/) { # @ MULTINAME
		$ttl = $1 || "";
		$line =~ s/;.*//; # strip comment
		$line =~ s/\([0-9]+\)//; # remove ttl
		($mname, @hosts) = split(/\s+/, $line);
		if ($#hosts == -1) {
			die "E2641 \@$.: Ey! ensam host på rad $.";
		}
		&multiname($mname, $ttl,  @hosts);
	} else {
		die "E1974 \@$.: Trasig rad: $line";
	}
}
close($INFILE) or die "close $inf: $!";
close($FORVFILE) or die "close $forwfiletmp: $!";
close($REVEFILE) or die "close $revefiletmp: $!";
if($reve6filename) { close($REVE6FILE) or die "close $reve6filetmp: $!"; }
#if($dhcpfilename) { close($DHCPFILE) or die "close $dhcpfiletmp: $!"; }

for my $group (keys %dhcpgroups) {
	last unless defined $ethersfilename;
	my $suffix=$group;
	if ($suffix ne '') {
		$suffix = '-'.$suffix;
	}
	my $data = $ethersdata{$group};
	if (!defined $data) {
		mywarn "WARNING: Empty dhcp/ethers group $group\n";
		$data = "# Empty group, fix me?\n";
	}
	print "Generating files for dhcp/ethers group [$group]\n";
	my($F, $fn) = tempfile("$ethersfilename$suffix.XXXXXX");
	print $F $data;
	close($F) or die "close $fn: $!";
	push @tmpfiles, $fn;
}
for my $group (keys %dhcpgroups) {
	last unless defined $dhcpfilename;
	my $suffix=$group;
	if ($suffix ne '') {
		$suffix = '-'.$suffix;
	}
	my $data = $dhcpdata{$group};
	if (!defined $data) {
		mywarn "WARNING: Empty dhcp group $group\n";
		$data = "# Empty group, fix me?\n";
	}
	print "Generating files for dhcp group [$group]\n";
	my($F, $fn) = tempfile("$dhcpfilename$suffix.XXXXXX");
	print $F $data;
	close($F) or die "close $fn: $!";
	push @tmpfiles, $fn;
}

for my $group (keys %dhcpgroups) {
	last unless defined $dhcp6filename;
	my $suffix=$group;
	if ($suffix ne '') {
		$suffix = '-'.$suffix;
	}
	my $data = $dhcp6data{$group};
	if (!defined $data) {
		mywarn "WARNING: Empty dhcp6 group $group\n";
		$data = "# Empty group, fix me?\n";
	}
	print "Generating files for dhcp6 group [$group]\n";
	my($F, $fn) = tempfile("$dhcp6filename$suffix.XXXXXX");
	print $F $data;
	close($F) or die "close $fn: $!";
	push @tmpfiles, $fn;
}

if($verbose) {
	print "Processing complete.\n";
	print "Generated temporary files:\n", join("\n", @tmpfiles), "\n";
}

if($dryrun) {
	unless($ENV{DEBUG}) {
		print "Removing generated temporary files.\n" if $verbose;
		unlink @tmpfiles or die "unlink tmpfiles: $!";
	}
}
else {
	chmod 0664 &~ umask(), @tmpfiles; # Honor umask, but never o+w ...
	foreach my $tmp (@tmpfiles) {
		my $fn = $tmp;
		$fn =~ s/\.[^\.]+$//;
		print "Rename $tmp -> $fn\n" if $verbose;
		rename $tmp, $fn or die "rename $tmp -> $fn: $!";
	}
}
