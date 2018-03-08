#!/usr/bin/env perl

# Copyright (C) Yichun Zhang (agentzh)

use v5.10.1;
use strict;
use warnings;

use sigtrap qw(die INT QUIT TERM);
use Time::HiRes qw( sleep );
use URI ();
use LWP::UserAgent ();
use JSON::XS ();
#use Data::Dumper qw( Dumper );
use File::Spec ();
use File::Copy qw( copy );
use File::Path qw( make_path );
use Digest::MD5 ();
use Getopt::Std qw( getopts );
use Cwd qw( cwd );

sub http_req ($$$);
sub main ();
sub process_cycle ();
sub gen_backup_file_prefix ();
sub shell (@);
sub read_ini ($);
sub err_log;

my $json_xs = JSON::XS->new;

my $version = '0.0.5';

my %opts;
getopts("di:", \%opts) or die;

my $as_daemon = $opts{d};
my $iterations = $opts{i} || 0;  # 0 means infinite

my $api_server_host = shift || "127.0.0.1";
my $api_server_port = shift || 8080;
my $failed_dir = shift || "/opm/failed";
my $original_dir = shift || "/opm/original";

my $SpecialDepPat = qr/^(?:openresty|luajit|ngx_(?:http_)?lua|nginx)$/;

my $name = "opm-pkg-indexer";
my $pid_file = File::Spec->rel2abs("$name.pid");

$ENV{LC_ALL} = 'C';

if (!-d $failed_dir) {
    make_path $failed_dir;
}

my $uri_prefix = "http://$api_server_host:$api_server_port";

my $ua = LWP::UserAgent->new;
$ua->agent("opm pkg indexer" . $version);

my $req = HTTP::Request->new();
$req->header(Host => "opm.openresty.org");

my $MAX_SLEEP_TIME = 1;  # sec
my $MAX_HTTP_TRIES = 3;
my $MAX_DEPS = 50;
#my $MAX_DEPS = 0;

if (-f $pid_file) {
    open my $in, $pid_file
        or die "cannot open $pid_file for reading: $!\n";
    my $pid = <$in>;
    close $in;

    chomp $pid;

    if (!$pid) {
        unlink $pid_file or die "cannot rm $pid_file: $!\n";

    } else {
        my $file = $pid_file;
        undef $pid_file;
        die "Found pid file $file. ",
            "Another process $pid may still be running.\n";
    }
}

if ($opts{d}) {
    my $log_file = "$name.log";

    require Proc::Daemon;

    my $daemon = Proc::Daemon->new(
        work_dir => cwd,
        child_STDOUT => "+>>$log_file",
        child_STDERR => "+>>$log_file",
        pid_file => $pid_file,
    );

    my $pid = $daemon->Init;
    if ($pid == 0) {
        # in the forked daemon

    } else {
        # in parent
        #err_log "write pid file $pid_file: $pid";
        #write_pid_file($pid);
        exit;
    }

} else {
    write_pid_file($$);
}

sub cleanup {
    if (defined $pid_file && -f $pid_file) {
        my $in;
        if (open $in, $pid_file) {
            my $pid = <$in>;
            if ($pid eq $$) {
                unlink $pid_file;
            }
            close $in;
        }
    }
}

END {
    cleanup();
    exit;
}

main();

unlink $pid_file or die "cannot remove $pid_file: $!\n";;

sub main () {
    my $sleep_time = 0.001;
    #err_log "iterations: $iterations";
    for (my $i = 1; $iterations <= 0 || $i <= $iterations; $i++) {
        my $ok;
        eval {
            $ok = process_cycle();
        };
        if ($@) {
            err_log "failed to process: $@";
        }

        if (!$ok) {
            #err_log $sleep_time;
            sleep $sleep_time;

            if ($sleep_time < $MAX_SLEEP_TIME) {
                $sleep_time *= 2;
            }

            next;
        }

        # ok
        $sleep_time = 0.001;
    }
}

sub process_cycle () {
    my ($data, $err) = http_req("/api/pkg/incoming", undef, undef);
    #warn Dumper($data);

    if ($err) {
        return;
    }

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
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        my $md5sum;
        {
            my $in;
            if (!open $in, $path) {
                $errstr = "cannot open $path for reading: $!";
                err_log $errstr;
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
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        #err_log "file $path found";

        my $cwd = File::Spec->catdir($incoming_dir, $account);
        if (!chdir $cwd) {
            $errstr = "failed to chdir to $cwd: $!";
            err_log $errstr;
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
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        my $dir = $dist_basename;
        if (!-d $dir) {
            $errstr = "directory $dir not found after unpacking $fname";
            goto FAIL_UPLOAD;
        }

        if (!chdir $dir) {
            $errstr = "failed to chdir to $dir: $!";
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        my $out = `ulimit -t 10 -v 204800 && opm server-build 2>&1`;
        if ($? != 0) {
            $errstr = "failed to run \"opm server-build\":\n$out";
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        my $final_file = "$name-$ver.opm.tar.gz";
        if (!-f $final_file) {
            $errstr = "failed to find $final_file from \"opm server-build\"";
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        my $final_md5;
        {
            my $in;
            if (!open $in, $final_file) {
                $errstr = "cannot open $final_file for reading: $!\n";
                err_log $errstr;
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
            $errstr = "failed to load $inifile: $errstr";
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        my $default_sec = $user_meta->{default};

        my $meta_name = $default_sec->{name};
        if (!$meta_name) {
            $errstr = "$inifile: no name found";
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        if ($meta_name ne $name) {
            $errstr = "$inifile: name \"$meta_name\" does not match \"$name\"";
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        my $meta_account = $default_sec->{account};
        if (!$meta_account) {
            $errstr = "$inifile: no account found";
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        if ($meta_account ne $account) {
            $errstr = "$inifile: account \"$meta_account\" does not match "
                      . "\"$account\"";
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        my $authors = $default_sec->{author};
        if (!$authors) {
            $errstr = "$inifile: no authors found";
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        $authors = [split /\s*,\s*/, $authors];

        my $repo_link = $default_sec->{repo_link};
        if (!$repo_link) {
            $errstr = "$inifile: no repo_link found";
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        my $is_orig = $default_sec->{is_original};
        if (!$is_orig) {
            $errstr = "$inifile: no repo_link found";
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        if ($is_orig eq 'yes') {
            $is_orig = 1;

        } elsif ($is_orig eq 'no') {
            undef $is_orig;

        } else {
            $errstr = "$inifile: bad is_original value: $is_orig";
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        my $abstract = $default_sec->{abstract};
        if (!$abstract) {
            $errstr = "$inifile: no abstract found";
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        my $license = $default_sec->{license};
        if (!$license) {
            $errstr = "$inifile: no license found";
            err_log $errstr;
            goto FAIL_UPLOAD;
        }

        my $licenses = [split /\s*,\s*/, $license];

        my $requires = $default_sec->{requires};
        my (@dep_pkgs, @dep_ops, @dep_vers);
        if ($requires) {
            my ($deps, $err) = parse_deps($requires, $inifile);
            if ($err) {
                $errstr = "$inifile: requires: $err";
                err_log $errstr;
                goto FAIL_UPLOAD;
            }

            my $ndeps = @$deps;
            if ($ndeps > $MAX_DEPS) {
                $errstr = "$inifile: too many dependencies: $ndeps";
                goto FAIL_UPLOAD;
            }

            for my $dep (@$deps) {
                my ($account, $name, $op, $ver) = @$dep;

                my ($op_arg, $ver_arg);

                if ($op && $ver) {
                    if ($op eq '>=') {
                        $op_arg = "ge";

                    } elsif ($op eq '=') {
                        $op_arg = "eq";

                    } elsif ($op eq '>') {
                        $op_arg = "gt";

                    } else {
                        $errstr = "bad dependency operator: $op";
                        err_log $errstr;
                        goto FAIL_UPLOAD;
                    }

                    $ver_arg = $ver;

                } else {
                    $op_arg = "";
                    $ver_arg = "";
                }

                die unless !defined $account || $account =~ /^[-\w]+$/;
                die unless $name =~ /^[-\w]+$/;

                if ($account) {
                    my $uri = "/api/pkg/exists?account=$account\&name=$name\&op=$op_arg&version=$ver_arg";
                    my ($res, $err) = http_req($uri, undef, { 404 => 1 });

                    if (!$res) {
                        my $spec;
                        if (!defined $op || !defined $ver) {
                            $spec = '';
                        } else {
                            $spec = " $op $ver";
                        }

                        $errstr = "package dependency check failed on \"$name$spec\": $err";
                        err_log $errstr;
                        goto FAIL_UPLOAD;
                    }

                    #warn $res->{found_version};
                }

                push @dep_pkgs, $account ? "$account/$name" : $name;
                push @dep_ops, $op || undef;
                push @dep_vers, $ver || undef;
            }
        }

        $dir = "../..";
        chdir $dir or err_log "cannot chdir $dir: $!";

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
                    err_log $@;
                }
            }

            if (!$failed) {
                my $dstfile = File::Spec->catfile($orig_subdir, $fname);

                if (!copy($path, $dstfile)) {
                    err_log "failed to copy $path to $dstfile: $!";
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

        {
            my $uri = "/api/pkg/processed";
            my ($res, $err) = http_req($uri, $json_xs->encode($meta), undef);
            if (!defined $res) {
                goto FAIL_UPLOAD;
            }
        }

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
                    err_log $@;
                }
            }

            my $prefix = gen_backup_file_prefix();
            my $dstfile = File::Spec->catfile($failed_subdir, "$prefix-$fname");

            copy($path, $dstfile)
                or err_log "failed to copy $path to $dstfile: $!";
        }

        if (-d $dist_dir) {
            shell "rm", "-rf", $dist_dir;
        }

        {
            my $uri = "/api/pkg/processed";
            my $meta = {
                id => $id,
                failed => 1,
                reason => $errstr,
                file => $path,
            };

            my ($res, $err) = http_req($uri, $json_xs->encode($meta), undef);
        }
    }
}

sub gen_backup_file_prefix () {
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime();
    return sprintf("%04d-%02d-%02d-%02d-%02d-%02d",
                   $year + 1900,  $mon + 1, $mday,
                   $hour, $min, $sec);
}

sub gen_timestamp () {
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime();
    return sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                   $year + 1900,  $mon + 1, $mday,
                   $hour, $min, $sec);
}

sub http_req ($$$) {
    my ($uri, $req_body, $no_retry_statuses) = @_;

    my $err;

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
            $err = "request to $uri failed: " . $resp->status_line . ": "
                   . ($resp->decoded_content || "");

            my $status = $resp->code;
            if ($status == 400
                || (defined $no_retry_statuses
                    && $no_retry_statuses->{$status}))
            {
                err_log $err;
                return undef, $err;
            }

            err_log "attempt $i of $MAX_HTTP_TRIES: $err";

            sleep $i * 0.001;
            next;
        }

        my $body = $resp->decoded_content;
        my $data;
        eval {
            $data = $json_xs->decode($body);
        };

        if ($@) {
            err_log "failed to decode JSON data $body for uri $uri: $@";
            sleep $i * 0.001;
            next;
        }

        return $data;
    }

    return undef, $err
}

sub shell (@) {
    if (system(@_) != 0) {
        my $cmd = join(" ", map { /\s/ ? "'$_'" : $_ } @_);
        err_log "failed to run the command \"$cmd\": $?";
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
        if ($item =~ m{^ ([-/\w]+) $}x) {
            my $full_name = $item;

            my ($account, $name);

            if ($full_name =~ m{^ ([-\w]+) / ([-\w]+)  }x) {
                ($account, $name) = ($1, $2);

            } elsif ($full_name =~ $SpecialDepPat) {
                $name = $full_name;

            } else {
                return undef, "$file: bad dependency name: $full_name";
            }

            push @parsed, [$account, $name];

        } elsif ($item =~ m{^ ([-/\w]+) \s* ([^\w\s]+) \s* (\w\S*) $}x) {
            my ($full_name, $op, $ver) = ($1, $2, $3);

            my ($account, $name);

            if ($full_name =~ m{^ ([-\w]+) / ([-\w]+)  }x) {
                ($account, $name) = ($1, $2);

            } elsif ($full_name =~ $SpecialDepPat) {
                $name = $full_name;

            } else {
                return undef, "$file: bad dependency name: $full_name";
            }

            if ($op !~ /^ (?: >= | = | > ) $/x) {
                return undef, "$file: bad dependency version comparison"
                              . " operator in \"$item\": $op";
            }

            if ($ver !~ /\d/ || $ver =~ /[^-.\w]/) {
                return undef, "$file: bad version number in dependency"
                              . " specification in \"$item\": $ver";
            }

            push @parsed, [$account, $name, $op, $ver];

        } else {
            return undef, "$file: bad dependency specification: $item";
        }
    }

    @parsed = sort { $a->[1] cmp $b->[1] } @parsed;
    return \@parsed;
}

sub write_pid_file {
    my $pid = shift;
    open my $out, ">$pid_file"
        or die "cannot open $pid_file for writing: $!\n";
    print $out $pid;
    close $out;
}

sub err_log {
    my @args = @_;
    my $ts = gen_timestamp();
    warn "[$ts] ", @args;
}
