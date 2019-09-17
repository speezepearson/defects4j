#-------------------------------------------------------------------------------
# Copyright (c) 2014-2019 René Just, Darioush Jalali, and Defects4J contributors.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#-------------------------------------------------------------------------------

=pod

=head1 NAME

Project::Mockito.pm -- L<Project> submodule for mockito.

=head1 DESCRIPTION

This module provides all project-specific configurations and methods for the
mockito project.

=cut
package Project::Mockito;

use strict;
use warnings;

use Constants;
use Vcs::Git;

our @ISA = qw(Project);
my $PID  = "Mockito";

sub new {
    @_ == 1 or die $ARG_ERROR;
    my ($class) = @_;

    my $name = "mockito";
    my $vcs  = Vcs::Git->new($PID,
                             "$REPO_DIR/$name.git",
                             "$PROJECTS_DIR/$PID/commit-db",
                             \&_post_checkout);

    return $class->SUPER::new($PID, $name, $vcs);
}

sub _post_checkout {
    my ($self, $rev_id, $work_dir) = @_;

    # Fix Mockito's test runners
    my $vid = $self->{_vcs}->lookup_vid($rev_id);
    # TODO: Testing for vids is super brittle! Find a better way to determine
    # whether a test class needs to be patched, or provide a patch for each
    # affected revision id.
    my $mockito_junit_runner_patch_file = "$PROJECTS_DIR/$PID/mockito_test_runners.patch";
    if ($vid == 16 || $vid == 17 || ($vid >= 34 && $vid <= 38)) {
        $self->apply_patch($work_dir, "$mockito_junit_runner_patch_file")
                or confess("Couldn't apply patch ($mockito_junit_runner_patch_file): $!");
    }

    # Change Url to Gradle distribution
    my $prop = "$work_dir/gradle/wrapper/gradle-wrapper.properties";
    my $lib_dir = "$BUILD_SYSTEMS_LIB_DIR/gradle/dists";

    # Read existing Gradle properties file, if it exists
    open(PROP, "<$prop") or return;
    my @tmp;
    while (<PROP>) {
        if (/(distributionUrl=).*\/(gradle-2.*)/) {
            s/(distributionUrl=).*\/(gradle-.*)/$1file\\:$lib_dir\/gradle-2.2.1-all.zip/g;
        } else {
            s/(distributionUrl=).*\/(gradle-.*)/$1file\\:$lib_dir\/gradle-1.12-bin.zip/g;
        }
        push(@tmp, $_);
    }
    close(PROP);

    # Update properties file
    open(OUT, ">$prop") or die "Cannot write properties file";
    print(OUT @tmp);
    close(OUT);

    # Disable the Gradle daemon
    if (-e "$work_dir/gradle.properties") {
        system("sed -i.bak s/org.gradle.daemon=true/org.gradle.daemon=false/g \"$work_dir/gradle.properties\"");
    }

    # Enable local repository
    system("find $work_dir -type f -name \"build.gradle\" -exec sed -i.bak 's|jcenter()|maven { url \"$BUILD_SYSTEMS_LIB_DIR/gradle/deps\" }\\\n jcenter()\\\n|g' {} \\;");
}

sub determine_layout {
    @_ == 2 or die $ARG_ERROR;
    my ($self, $rev_id) = @_;
    my $work_dir = $self->{prog_root};
    if (-e "$work_dir/src/main/java") {
        return {src=>"src/main/java", test=>"src/test/java"};
    } elsif(-e "$work_dir/src") {
        return {src=>"src", test=>"test"};
    } else {
        die "Unknown directory layout";
    }
}

sub _ant_call {
    @_ >= 2 or die $ARG_ERROR;
    my ($self, $target, $option_str, $log_file) =  @_;

    # By default gradle uses $HOME/.gradle, which causes problems when multiple
    # instances of gradle run at the same time.
    #
    # TODO: Extract all exported environment variables into a user-visible
    # config file.
    $ENV{'GRADLE_USER_HOME'} = "$self->{prog_root}/$GRADLE_LOCAL_HOME_DIR";
    return $self->SUPER::_ant_call($target, $option_str, $log_file);
}

1;
