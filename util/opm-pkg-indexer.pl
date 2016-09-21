#!/usr/bin/env perl

# Copyright (C) Yichun Zhang (agentzh)

use strict;
use warnings;

use Time::HiRes qw( sleep );
use URI ();
use LWP::UserAgent ();
use JSON::XS ();
#use Data::Dumper qw( Dumper );
use File::Spec ();
use File::Copy qw( copy );
use File::Path qw( make_path );
use Digest::MD5 ();

sub http_req ($$);
sub main ();
sub process_cycle ();
sub gen_backup_file_prefix ();
sub shell (@);
sub read_ini ($);

my $json_xs = JSON::XS->new->utf8;

my $version = '0.0.1';

my $api_server_host = shift || "127.0.0.1";
my $api_server_port = shift || 8080;
my $failed_dir = shift || "/tmp/failed";
my $original_dir = shift || "/tmp/original";

$ENV{LC_ALL} = 'C';

if (!-d $failed_dir) {
    make_path $failed_dir;
}

my $uri_prefix = "http://$api_server_host:$api_server_port";

my $ua = LWP::UserAgent->new;
$ua->agent("opm pkg indexer" . $version);

my $req = HTTP::Request->new();
$req->header(Host => "opm.openresty.org");

my $MAX_FAILS = 100;
my $MAX_HTTP_TRIES = 10;

main();

sub main () {
    my $fails = 0;
    #while (1) {
    for (1) {
        my $ok;
        eval {
            $ok = process_cycle();
        };
        if ($@) {
            warn "failed to process: $@";
        }

        if (!$ok) {
            sleep 0.001 * $fails;

            if ($fails < $MAX_FAILS) {
                $fails++;
            }

            next;
        }

        # ok
        $fails = 0;
    }
}

sub process_cycle () {
    my $data = http_req("/api/incoming", undef);
    #warn Dumper($data);

    my $incoming_dir = $data->{incoming_dir} or die;
    my $final_dir = $data->{final_dir} or die;

    my $uploads = $data->{uploads};
    my $errstr;

    for my $upload (@$uploads) {
        #warn Dumper($upload);
        my $id = $upload->{id} or die "id not defined";
        my $name = $upload->{name} or die "name not defined";
        my $ver = $upload->{version_s} or die "version_s not defined";
        my $uploader = $upload->{uploader} or die "uploader not defined";
        my $org_account = $upload->{org_account};
        my $orig_checksum = $upload->{orig_checksum}
            or die "orig_checksum not defined";
        $orig_checksum =~ s/-//g;

        my $account;
        if ($org_account) {
            $account = $org_account;

        } else {
            $account = $uploader;
        }

        my $fname = "$name-$ver.tar.gz";

        #warn $fname;
        my $path = File::Spec->catfile($incoming_dir, $account, $fname);
        if (!-f $path) {
            $errstr = "file $path does not exist";
            warn $errstr;
            goto FAIL_UPLOAD;
        }

        my $md5sum;
        {
            my $in;
            if (!open $in, $path) {
                $errstr = "cannot open $path for reading: $!";
                warn $errstr;
                goto FAIL_UPLOAD;
            }

            my $ctx = Digest::MD5->new;
            $ctx->addfile($in);
            $md5sum = $ctx->hexdigest;
            close $in;
        }

        if ($md5sum ne $orig_checksum) {
            $errstr = "MD5 checksum for the original package mismatch: "
                      . "$md5sum vs $orig_checksum\n";
            warn $errstr;
            goto FAIL_UPLOAD;
        }

        #warn "file $path found";

        my $cwd = File::Spec->catdir($incoming_dir, $account);
        if (!chdir $cwd) {
            $errstr = "failed to chdir to $cwd: $!";
            warn $errstr;
            goto FAIL_UPLOAD;
        }

        my $dist_basename = "$name-$ver";
        my $dist_dir = File::Spec->rel2abs(
                            File::Spec->catdir($cwd, $dist_basename));

        if (-d $dist_dir) {
            shell "rm", "-rf", $dist_dir;
        }

        if (!shell "tar", "-xzf", $path) {
            $errstr = "failed to unpack $fname";
            warn $errstr;
            goto FAIL_UPLOAD;
        }

        my $dir = $dist_basename;
        if (!-d $dir) {
            $errstr = "directory $dir not found after unpacking $fname";
            goto FAIL_UPLOAD;
        }

        if (!chdir $dir) {
            $errstr = "failed to chdir to $dir $!";
            warn $errstr;
            goto FAIL_UPLOAD;
        }

        if (!shell "ulimit -t 10 -v 204800 && opm server-build") {
            $errstr = "failed to run \"opm server-build\"";
            warn $errstr;
            goto FAIL_UPLOAD;
        }

        my $final_file = "$name-$ver.opm.tar.gz";
        if (!-f $final_file) {
            $errstr = "failed to find $final_file from \"opm server-build\"";
            warn $errstr;
            goto FAIL_UPLOAD;
        }

        my $final_md5;
        {
            my $in;
            if (!open $in, $final_file) {
                $errstr = "cannot open $final_file for reading: $!\n";
                warn $errstr;
                goto FAIL_UPLOAD;
            }

            my $ctx = Digest::MD5->new;
            $ctx->addfile($in);
            #$ctx->add("foo");
            $final_md5 = $ctx->hexdigest;
            close $in;
        }

        {
            my $final_subdir = File::Spec->catdir($final_dir, $account);

            if (!-d $final_subdir) {
                eval {
                    make_path $final_subdir;
                };
                if ($@) {
                    # failed
                    $errstr = $@;
                    goto FAIL_UPLOAD;
                }
            }

            my $dstfile = File::Spec->catfile($final_subdir, $final_file);

            if (!copy($final_file, $dstfile)) {
                $errstr = "failed to copy $path to $dstfile: $!";
                goto FAIL_UPLOAD;
            }
        }

        my $inifile = "dist.ini";
        my ($user_meta, $err) = read_ini($inifile);
        if (!$user_meta) {
            $errstr = $err;
            warn "failed to load $inifile: $errstr";
            goto FAIL_UPLOAD;
        }

        my $default_sec = $user_meta->{default};

        my $authors = $default_sec->{author};
        if (!$authors) {
            $errstr = "$inifile: no authors found";
            warn $errstr;
            goto FAIL_UPLOAD;
        }

        $authors = [split /\s*,\s*/, $authors];

        my $repo_link = $default_sec->{repo_link};
        if (!$repo_link) {
            $errstr = "$inifile: no repo_link found";
            warn $errstr;
            goto FAIL_UPLOAD;
        }

        my $is_orig = $default_sec->{is_original};
        if (!$is_orig) {
            $errstr = "$inifile: no repo_link found";
            warn $errstr;
            goto FAIL_UPLOAD;
        }

        if ($is_orig eq 'yes') {
            $is_orig = 1;

        } elsif ($is_orig eq 'no') {
            undef $is_orig;

        } else {
            $errstr = "$inifile: bad is_original value: $is_orig";
            warn $errstr;
            goto FAIL_UPLOAD;
        }

        my $abstract = $default_sec->{abstract};
        if (!$abstract) {
            $errstr = "$inifile: no abstract found";
            warn $errstr;
            goto FAIL_UPLOAD;
        }

        my $license = $default_sec->{license};
        if (!$license) {
            $errstr = "$inifile: no license found";
            warn $errstr;
            goto FAIL_UPLOAD;
        }

        my $licenses = [split /\s*,\s*/, $license];

        my $requires = $default_sec->{requires};
        my (@dep_pkgs, @dep_ops, @dep_vers);
        if ($requires) {
            my ($deps, $err) = parse_deps($requires);
            if ($err) {
                $errstr = "$inifile: requires: $err";
                warn $errstr;
                goto FAIL_UPLOAD;
            }

            for my $dep (@$deps) {
                my ($name, $op, $ver) = @$dep;

                if (!$op && $ver) {
                    $op = ">=";
                }

                push @dep_pkgs, $name;
                push @dep_ops, $op;
                push @dep_vers, $ver || undef;
            }
        }

        $dir = "../..";
        chdir $dir or warn "cannot chdir $dir: $!";

        if (-d $dist_dir) {
            shell "rm", "-rf", $dist_dir;
        }

        {
            # back up the original user uploaded file into original_dir.

            my $orig_subdir = File::Spec->catdir($original_dir, $account);
            my $failed;

            if (!-d $orig_subdir) {
                eval {
                    make_path $orig_subdir;
                };
                if ($@) {
                    # failed
                    $failed = 1;
                    warn $@;
                }
            }

            if (!$failed) {
                my $dstfile = File::Spec->catfile($orig_subdir, $fname);

                if (!copy($path, $dstfile)) {
                    warn "failed to copy $path to $dstfile: $!";
                }
            }
        }

        my $meta = {
            id => $id,
            authors => $authors,
            abstract => $abstract,
            licenses => $licenses,
            is_original => $is_orig,
            repo_link => $repo_link,
            final_checksum => $final_md5,
            dep_packages => \@dep_pkgs,
            dep_operators => \@dep_ops,
            dep_versions => \@dep_vers,
            file => $path,
        };

        my $uri = "/api/processed";
        my $res = http_req($uri, $json_xs->encode($meta));

        next;

FAIL_UPLOAD:

        if (-f $path) {
            my $failed_subdir = File::Spec->catdir($failed_dir, $account);

            if (!-d $failed_subdir) {
                eval {
                    make_path $failed_subdir;
                };
                if ($@) {
                    # failed
                    warn $@;
                }
            }

            my $prefix = gen_backup_file_prefix();
            my $dstfile = File::Spec->catfile($failed_subdir, "$prefix-$fname");

            copy($path, $dstfile)
                or warn "failed to copy $path to $dstfile: $!";
        }

        if (-d $dist_dir) {
            shell "rm", "-rf", $dist_dir;
        }

        {
            my $uri = "/api/processed";
            my $meta = {
                id => $id,
                failed => 1,
                reason => $errstr,
                file => $path,
            };
            my $res = http_req($uri, $json_xs->encode($meta));
        }
    };
}

sub gen_backup_file_prefix () {
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime();
    return sprintf("%04d-%02d-%02d-%02d-%02d-%02d",
                   $year + 1900,  $mon + 1, $mday,
                   $hour, $min, $sec);
}

sub http_req ($$) {
    my ($uri, $req_body) = @_;

    for my $i (1 .. $MAX_HTTP_TRIES) {
        # send request
        $req->uri("$uri_prefix$uri");

        $req->method($req_body ? "PUT" : "GET");

        if ($req_body) {
            $req->content($req_body);
        }

        my $resp = $ua->request($req);

        # check the outcome
        if (!$resp->is_success) {
            warn "request to $uri failed: ", $resp->status_line, ": ",
                 $resp->decoded_content;

            sleep $i * 0.001;
            next;
        }

        my $body = $resp->decoded_content;
        my $data;
        eval {
            $data = $json_xs->decode($body);
        };

        if ($@) {
            warn "failed to decode JSON data $body for uri $uri: $@";
            sleep $i * 0.001;
            next;
        }

        return $data;
    }
}

sub shell (@) {
    if (system(@_) != 0) {
        my $cmd = join(" ", map { /\s/ ? "'$_'" : $_ } @_);
        warn "failed to run the command \"$cmd\": $?";
        return undef;
    }

    return 1;
}

sub read_ini ($) {
    my $infile = shift;

    my $in;
    if (!open $in, $infile) {
        return undef, "cannot open $infile for reading: $!";
    }

    my %sections;
    my $sec_name = 'default';
    my $sec = ($sections{$sec_name} = {});

    local $_;
    while (<$in>) {
        next if /^\s*$/ || /^\s*[\#;]/;

        if (/^ \s* (\w+) \s* = \s* (.*)/x) {
            my ($key, $val) = ($1, $2);
            $val =~ s/\s+$//;
            if (exists $sec->{$key}) {
                return undef, "$infile: line $.: duplicate key in section "
                              . "\"$sec_name\": $key\n";
            }
            $sec->{$key} = $val;
            next;
        }

        if (/^ \s* \[ \s* ([^\]]*) \] \s* $/x) {
            my $name = $1;
            $name =~ s/\s+$//;
            if ($name eq '') {
                return undef, "$infile: line $.: section name empty";
            }

            if (exists $sections{$name}) {
                return undef, "$infile: line $.: section \"$name\" redefined";
            }

            $sec = {};
            $sections{$name} = $sec;
            $sec_name = $name;

            next;
        }

        return undef, "$infile: line $.: syntax error: $_";
    }

    close $in;

    return \%sections;
}

sub parse_deps {
    my ($line, $file) = @_;
    my @items = split /\s*,\s*/, $line;
    my @parsed;
    for my $item (@items) {
        if ($item =~ /^[-\w]+$/) {
            push @parsed, [$item];

        } elsif ($item =~ /^ ([-\w]+) \s* (\S+) \s* (\S+) $/x) {
            my ($name, $op, $ver) = ($1, $2, $3);

            if ($op !~ /^ (?: >= | = ) $/x) {
                return undef, "$file: bad dependency version comparison"
                              . " operator in \"$item\": $op";
            }

            if ($ver !~ /\d/ || $ver =~ /[^-.\w]/) {
                return undef, "$file: bad version number in dependency"
                              . " specification in \"$item\": $ver";
            }

            push @parsed, [$name, $op, $ver];

        } else {
            return undef, "$file: bad dependency specification: $item";
        }
    }

    @parsed = sort { $a->[0] cmp $b->[0] } @parsed;
    return \@parsed;
}
