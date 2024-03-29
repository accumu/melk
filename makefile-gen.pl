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


use warnings;
#use strict; # FIXME

#Example from cs in Makefile.in:
#cs.umu.se               130.239.40      2001:6b0:e:4040
#cs.umu.se               130.239.41      2001:6b0:e:4041
#cs.umu.se               130.239.42      2001:6b0:e:4042
#cs.umu.se               130.239.88      -
#cs.umu.se               130.239.89      -
#backdoor.cs.umu.se      192.168.10      -
#ray.cs.umu.se           192.168.16      -
#printer.cs.umu.se       192.168.40      -
#dklab.cs.umu.se         192.168.100     -

open(F, "<", "Makefile.in") || die "Makefile.in: $!";
open(FO, ">", "Makefile.out") || die "Makefile.out: $!";

print FO "SRC=melk\n";
print FO "MELK=./melk.pl\n";
print FO "CSN=./change-serial-number\n";

my $str = "";
while(<F>) {
	if (/^(\S+)\s+(\S+)\s+(\S+)/) {
		$dom = $1; $v4prefix=$2;$v6prefix=$3;
		$v6prefixcomp = $v6prefix;
		$v6prefixcomp =~ s/://g;
		print "domain=[$dom] ip=[$v4prefix] v6=[$v6prefix]\n";
		push @files, "$dom/forw-$dom-$v4prefix";
		if ($v6prefix eq '-') {
		$str .= sprintf <<EOM;
$dom/forw-$dom-$v4prefix:	\$(SRC)/cs-$v4prefix.melk
	-chmod u+w $dom/forw-$dom-$v4prefix $v4prefix/rev-$v4prefix-$dom
	\$(MELK) \$(SRC)/cs-$v4prefix.melk mail.cs.umu.se. $dom $v4prefix
	\$(CSN) $dom/$dom.header
	\$(CSN) $v4prefix/rev.header
	chmod u-w $dom/forw-$dom-$v4prefix $v4prefix/rev-$v4prefix-$dom

EOM
		} else {
		$str .= sprintf <<EOM;
$dom/forw-$dom-$v4prefix:	\$(SRC)/cs-$v4prefix.melk
	-chmod u+w $dom/forw-$dom-$v4prefix $v4prefix/rev-$v4prefix-$dom $v6prefixcomp/rev-$v6prefixcomp-$dom
	\$(MELK) \$(SRC)/cs-$v4prefix.melk mail.cs.umu.se. $dom $v4prefix ${v6prefix}::
	\$(CSN) $dom/$dom.header
	\$(CSN) $v4prefix/rev.header
	\$(CSN) $v6prefixcomp/rev.header
	chmod u-w $dom/forw-$dom-$v4prefix $v4prefix/rev-$v4prefix-$dom $v6prefixcomp/rev-$v6prefixcomp-$dom

EOM
		}
	}
	
}
close(F);

printf FO "all: %s\n\n",join(" ", @files);
print FO $str;
close(FO);

