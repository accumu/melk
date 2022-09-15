# melk
DNS zone management made easy

# How this works

1) write your source, syntax described below
2) run melk


The program syntax is:
```
$0 <source file> <mx> <domain> <network>
```
Example:
```
melk.pl	acc.umu.se.melk mail acc.umu.se 130.239.18
```

The output is placed in two filed: `forv-$domain-$network` and
`reve-$network-$domain` which you can include in your master file.

Optionally give `$0 <source file> <mx> <domain> <network> <v6prefix>` for
ipv6 generation too. This will generate AAAA-records and a separate
reverse file for all hosts, unless otherwise specified.

The v6prefix should have a `::` at the end and melk will generate 64-bit
v6 host parts. If there is something following the `::` it will be used
as a prefix in the host part.

Optionally give `$0 <source file> <mx> <domain> <network> <v6prefix> <subnet>`
for subnets smaller than a /24. If you don't want ipv6 give `-` as v6prefix.

Complex example:
```
melk.pl hpc2n-46.0.melk mail.hpc2n.umu.se. hpc2n.umu.se 130.239.46 2001:6b0:e:4a46::a 0
```

Will generate a zone-file for `2001:6b0:e:4a46` containing host-part entries
like `0:0:a:42` assuming you have simple host definitions like `42 manwe`. The
v4 files will be in a `130.239.46` directory, but have a `.0` suffix to keep them
separate from other subnets starting with `130.239.46`.

The files are assumed to be used by a main zonefile with includes, like this:

```
; SOA and stuff
$INCLUDE /etc/bind/acc/acc.umu.se/acc.umu.se.header
; melk-generated files
$INCLUDE /etc/bind/acc/acc.umu.se/forw-acc.umu.se-130.239.18.0-acc-18.0
$INCLUDE /etc/bind/acc/acc.umu.se/forw-acc.umu.se-130.239.18.32-acc-18.32
; things not in melk
$INCLUDE /etc/bind/acc/acc.umu.se/acc-additional.db
```

# Source file syntax

1) an empty line, consist of zero or more spaces/tabs. these lines insert
an empty line into both output files, example:
```
```

2) an ipdata line, this consists of the ip address followed by one or
more hostnames, example:
```
206 jagular
154 caesar julius
```

If an ipdata line contains a `hostname` with a `:` in it, that is interpreted
as a mac address for dhcp file generation.

If a `hostname` is a `-` followed by one char, this will be used as a flag
and not hostname or aliases. Currently these flags are in use:
* `-4`: Only generate ipv4 adress for this host
* `-6`: Only generate ipv6 adress for this host

More complex examples (only generate ipv4 entry):
```
154 caesar julius 00:09:3D:00:1C:54 -4
```

3) an additional rr line, begins with a `+` followed by an
optional space. these lines are inserted into the forward-file with
tabs inserted in front of them, example:
```
+HINFO "SS 670MP" "SunOS 5.6"
```

4) multi name line, begins with a multiname followed by one or more
hostnames. the hostname must be the first name in the ipdata-line.  the
multiname can optionally be followed by two parentheis containing the ttl for
this entry, example:
```
login   shaka monte
ftp(600)    napoleon tutankhamon
```

5) verbatim lines. theses are inserterted directly into the forward or the
reverse file. if the line begin with a `<` its inserted into the reverse file
and `>` lines are inserted into the forward file, `|` inserts into both files. the
`<|>` can optionally be followed by a space. the `<|>` are removed from the
line.

`&` is the ipv6 reverse file equivalent of `<`.

Example:
```
| ; comment in both files
> 			HINFO "thing" "things"
< ; comment in reverse file
& ; comment in ipv6 reverse file
```

6) internal comments. this is just a comment and these lines are ignored,
useful for internal info, modelines, etc. Example:
```
# this melk file is unpublished proprietary source code of ACC
```

7) comment, lines starting with a semi colon `;`, these lines are inserted
into both output files, example:
```
; this is a useful comment known to anyone that can AXFR
```

8) CNAME, lines starting with a star `*`, these lines consists of first a
host and then a number of names that ends up as CNAME-entries.
Note that tabs aren't allowed!
Example:
```
* ftp nyancat xn--og8hss rainbowcat
Will turn out as:
nyancat      CNAME ftp
xn--og8hss   CNAME ftp
rainbowcat   CNAME ftp
```
