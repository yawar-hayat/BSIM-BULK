#!/bin/sh
eval 'exec perl -S -x -w $0 ${1+"$@"}'
#!perl

# Copyright © Silicon Integration Initiative, Inc., All rights reserved.
#
# Disclaimer of Warranty
# Software is provided "as is" and without warranty. Silicon Integration Initiative, Inc.,
# makes no warranties, express or implied with respect to software including any
# warranty of merchantability or fitness for a particular purpose.
#
# Limitation of Liability
# Silicon Integration Initiative is not liable for any property damage, personal injury,
# loss of profits, interruption of business, or for any other special consequential or
# incidental damages, however caused, whether for breach of warranty, contract tort
# (including negligence), strict liability, or otherwise.

#
# runQaTests.pl: program to run automated QA tests on compact models
#
#  Rel   Date            Who              Comments
#  ====  ==========      =============    ========
#  3.5   08/09/2023      Geoffrey Coram   Compare variant to reference if standard is missing
#  2.0   06/07/17        Shahriar Moinian Added SI2 clauses
#  1.11  11/28/2016      Geoffrey Coram   Allow testing of "expected failures"
#  1.9   12/12/2015      Geoffrey Coram   Support operating-point information
#                                         -o option to specify output dir
#                                         Cache determination of VA model card support
#        ??/??/2012      Ramses vdToorn   Update syntax (defined(%hash) is deprecated)
#  1.2   06/30/2006      Colin McAndrew   Floating node support added
#  1.0   04/13/2006      Colin McAndrew   Initial version
#

sub usage() {
    print "
$prog: run model QA tests

Usage: $prog [options] -s simulatorName qaSpecificationFile

Files:
    qaSpecificationFile    file with specifications for QA tests
    simulatorName          name of simulator to be tested

Options:
    -c version platform    do not try to simulate, only compare results for version and platform
    -d                     debug mode (leave intermediate files around)
    -h                     print this help message
    -i                     print info on file formats and structure
    -l                     list tests and variants that are defined
    -lt                    list tests that are defined
    -lv                    list test variants that are defined
    -nw                    do not print warning messages
    -o OUTDIR              place results in OUTDIR (bypass simulator version/platform determination)
    -platform              prints the hardware platform and operating system version
    -r                     re-use previously simulated results if they exist
                           (default is to resimulate, even if results exist)
    -sv                    prints the simulator and Verilog-A versions being run
    -sc simulatorCommand   run the simulator using simulator command (default is defined in simulatorName.pm file)
    -t   TEST              only run test TEST   (can be a comma delimited list)
    -var VAR               only run variant VAR (can be a comma delimited list)
    -v                     verbose mode
    -V                     really verbose mode, print out each difference detected
";
} # End of usage

sub info() {
    print "
This program runs automated QA tests on a model.
The test specifications are defined in the qaSpecificationFile
Each test is run by setting up a netlist, running this is in
the simulator in which the implementation of a model is being
tested, and then collating the simulation results. Because the
netlist formats, simulator commands, and output formats
vary between simulators, a specific set of routines that
run the tests must be provided for each simulator.

Please see the documentation for more details.
";
} # End of info

#
#   Set program names and variables
#

$\="\n";
$,=" ";
undef($number);
$number='[+-]?\d+[\.]?\d*[eE][+-]?\d+|[+-]?[\.]\d+[eE][+-]?\d+|[+-]?\d+[\.]?\d*|[+-]?[\.]\d+';
undef($qaSpecFile);
undef(@Setup);
undef(@Test);
undef(@Variants);
undef(@TestVariants);
$debug=0;
$verbose=0;
$reallyVerbose=0;
$doPlot=0;
$listTests=0;
$listVariants=0;
$onlyDoSimulatorVersion=0;
$onlyDoPlatformVersion=0;
$onlyDoComparison=0;
$forceSimulation=1;
$printWarnings=1;
@prog=split("/",$0);
$programDirectory=join("/",@prog[0..$#prog-1]);
$prog=$prog[$#prog];
$outputDir="";

#
#   These variables are only set or used once in this file,
#   and so generate unsightly warnings from the -w option
#   to perl; these undef's stop those warnings.
#

undef($mFactor);undef($shrinkPercent);undef($scaleFactor);undef(%TestSpec);
undef($simulatorCommand);

#
#   These are the tolerances used to compare results
#

$dcClip=1.0e-13;
$dcNdigit=6;
$dcRelTol=1.0e-6;

$acClip=1.0e-20;
$acNdigit=6;
$acRelTol=1.0e-6;

$noiseClip=1.0e-30;
$noiseNdigit=5;
$noiseRelTol=1.0e-5;

#
#   These are the values used to test shrink, scale, and m
#   (if they are requested to be tested).
#

$scaleFactor=1.0e-6;
$shrinkPercent=50;
$sqrt_mFactor=10;
$mFactor=$sqrt_mFactor*$sqrt_mFactor;

#
#   Parse the command line arguments
#

for (;;) {
    if (!defined($ARGV[0])) {
        last;
    } elsif ($ARGV[0] =~ /^-c/) {
        shift(@ARGV);
        if ($#ARGV<0) {die("ERROR: no simulator version specified for -c option, stopped")}
        $version=$ARGV[0];
        shift(@ARGV);
        if ($#ARGV<0) {die("ERROR: no platform specified for -c option, stopped")}
        $platform=$ARGV[0];
        $onlyDoComparison=1;
    } elsif ($ARGV[0] =~ /^-d/i) {
        $debug=1;$verbose=1;
    } elsif ($ARGV[0] =~ /^-h/i) {
        &usage();exit(0);
    } elsif ($ARGV[0] =~ /^-i/i) {
        &usage();&info();exit(0);
    } elsif ($ARGV[0] =~ /^-lv/i) {
        $listVariants=1;
    } elsif ($ARGV[0] =~ /^-lt/i) {
        $listTests=1;
    } elsif ($ARGV[0] =~ /^-l/i) {
        $listTests=1;$listVariants=1;
    } elsif ($ARGV[0] =~ /^-platform/i) {
        $onlyDoPlatformVersion=1;
    } elsif ($ARGV[0] =~ /^-nw/i) {
        $printWarnings=0;
    } elsif ($ARGV[0] =~ /^-o/i) {
        shift(@ARGV);
        if ($#ARGV<0) {die("ERROR: no output directory for -o option, stopped")}
        $outputDir=$ARGV[0];
    } elsif ($ARGV[0] =~ /^-p/i) {
        $doPlot=1;
    } elsif ($ARGV[0] =~ /^-r/i) {
        $forceSimulation=0;
    } elsif ($ARGV[0]  =~ /^-sv/i) {
        $onlyDoSimulatorVersion=1;
    } elsif ($ARGV[0] =~ /^-sc/i) {
        shift(@ARGV);
        if ($#ARGV<0) {die("ERROR: no simulator command for -sc option, stopped")}
        $simulatorCommand=$ARGV[0];
    } elsif ($ARGV[0] =~ /^-s/) {
        shift(@ARGV);
        if ($#ARGV<0) {die("ERROR: no simulator specified for -s option, stopped")}
        $simulatorName=$ARGV[0];
    } elsif ($ARGV[0] =~ /^-t/) {
        shift(@ARGV);
        if ($#ARGV<0) {die("ERROR: no test(s) specified for -t option, stopped")}
        foreach (split(/,/,$ARGV[0])) {$doTest{$_}=1}
    } elsif ($ARGV[0] =~ /^-var/) {
        shift(@ARGV);
        if ($#ARGV<0) {die("ERROR: no variant(s) specified for -var option, stopped")}
        foreach (split(/,/,$ARGV[0])) {$doVariant{$_}=1}
    } elsif ($ARGV[0] =~ /^-v/) {
        $verbose=1;
    } elsif ($ARGV[0] =~ /^-V/) {
        $verbose=1;$reallyVerbose=1;
    } elsif ($ARGV[0] =~ /^-/) {
        &usage();
        die("ERROR: unknown flag $ARGV[0], stopped");
    } else {
        last;
    }
    shift(@ARGV);
}
if ($onlyDoSimulatorVersion && !defined($simulatorName) && defined($ARGV[0])) {
    $simulatorName=$ARGV[0]; # assume -sv simulatorName was specified
}
if ($#ARGV<0 && !$onlyDoPlatformVersion && !($onlyDoSimulatorVersion && defined($simulatorName))) {
    &usage();exit(0);
}
if (!$onlyDoPlatformVersion && !defined($simulatorName)) {
    &usage();exit(0);
}

#
#   Source perl modules with subroutines that are called to do all the work
#

if (! require "$programDirectory/modelQaTestRoutines.pm") {
    die("ERROR: problem sourcing modelQaTestRoutines.pm, stopped");
}
if (!$onlyDoComparison) {
    $platform=&modelQa::platform();
    if ($onlyDoPlatformVersion) {
        print $platform;exit(0);
    }
    if (! -r "$programDirectory/$simulatorName.pm") {
        die("ERROR: there is no test routine Perl module for simulator $simulatorName, stopped");
    }
    if (! require "$programDirectory/$simulatorName.pm") {
        die("ERROR: problem sourcing test routine Perl module for simulator $simulatorName, stopped");
    }
}

#
#   Initial processing, set up directory names and process the QA specification file
#

if (!$onlyDoComparison && !$listTests && !$listVariants && ($outputDir eq "" || $onlyDoSimulatorVersion)) {
    ($version,$vaVersion)=&simulate::version();
}
$qaSpecFile=$ARGV[0];
$resultsDirectory="results";
$refrnceDirectory="reference";

if ($onlyDoComparison) {
    $resultsDirectory.="/$simulatorName/$version/$platform";
} elsif (!$listTests && !$listVariants) {
    if($outputDir eq "") {
        if (! -d $resultsDirectory) {mkdir($resultsDirectory,0775)}
        $resultsDirectory.="/$simulatorName";
        if (! -d $resultsDirectory) {mkdir($resultsDirectory,0775)}
        $resultsDirectory.="/$version";
        if (! -d $resultsDirectory) {mkdir($resultsDirectory,0775)}
        $resultsDirectory.="/$platform";
        if (! -d $resultsDirectory) {mkdir($resultsDirectory,0775)}
    } else {
        $resultsDirectory="";
        $sep="";
        @parts=split("/",$outputDir);
        foreach $part (@parts) {
            $resultsDirectory.="$sep$part";
            if (! -d $resultsDirectory) {mkdir($resultsDirectory,0775)}
            $sep="/";
        }
    }

    # Cache determination of Verilog-A model card support (if necessary) in the results directory
    if (defined($simulate::vaUseModelCard) && $simulate::vaUseModelCard == 1) {
        open(FH, ">$resultsDirectory/vaUseModelCard");
        close(FH);
    }
}

if ($onlyDoSimulatorVersion) {
    print $version,$vaVersion;
    exit(0);
}

undef(%Defined);
$Defined{$simulatorName}=1; # any `ifdef's in the QA spec file for $simulatorName are automatically included
&modelQa::readQaSpecFile();

&modelQa::processSetup(@Setup);

#
#   List tests and variants, if that was all that was requested
#   (note that the Makefile uses output from -lt and -lv
#   options to loop over the tests and variants individually,
#   so the output for those needs to be on a single line)
#

if ($listTests || $listVariants) {
    if ($listTests && $listVariants) {
        print "\nTests:";
        foreach (@Test) {print "    ".$_}
        print "\nVariants:";
        foreach (@Variants) {print "    ".$_}
    } elsif ($listTests) {
        print @Test;
    } else {
        print @Variants;
    }
    exit(0);
}

#
#   Loop over and run all tests
#   Note that the "standard" variant test is compared
#   to the reference results, whereas the other variant
#   tests are compared to the "standard" variant result.
#   This is because there may be some slight differences
#   between implementations, which get flagged when standard
#   is compared to reference, however for the other variants
#   this would generate a sequence of identical and in-exact
#   comparison messages. Each variant should *exactly* match
#   the standard, hence this is checked, and gives cleaner
#   looking output when the standard differs from the reference.
#

if ($reallyVerbose) {
    $flag="-v";
} else {
    $flag="";
}
foreach $test (@Test) {
    next if (%doTest && !$doTest{$test});

    if ($verbose) {print "\n****** Running test ($simulatorName): $test"}

    undef($outputDc);
    undef($outputAc);
    undef($outputNoise);
    undef($outputOp);
    undef($expectError);
    &modelQa::processTestSpec(@{$TestSpec{$test}});
    foreach $variant (@TestVariants) {
        $refFile="$resultsDirectory/$test.standard";
        if ($variant eq "standard" || !(-r $refFile)) {
            $refFile="$refrnceDirectory/$test.standard";
        }
        next if (%doVariant && !$doVariant{$variant});
        $simFile="$resultsDirectory/$test.$variant";
        if ($outputDc || $outputOp) {
            if (($forceSimulation || ! -r $simFile) && !$onlyDoComparison) {
                &simulate::runDcTest($variant,$simFile);
            }
            $clip=$dcClip;$relTol=$dcRelTol;$ndigit=$dcNdigit;
        }
        if ($outputAc) {
            if (($forceSimulation || ! -r $simFile) && !$onlyDoComparison) {
                &simulate::runAcTest($variant,$simFile);
            }
            $clip=$acClip;$relTol=$acRelTol;$ndigit=$acNdigit;
        }
        if ($outputNoise) {
            if (($forceSimulation || ! -r $simFile) && !$onlyDoComparison) {
                &simulate::runNoiseTest($variant,$simFile);
            }
            $clip=$noiseClip;$relTol=$noiseRelTol;$ndigit=$noiseNdigit;
        }
        if ($expectError) {
            $error = "-e";
        } else {
            $error = "";
        }
        if (-r $refFile && -r $simFile) {
            $message=sprintf("     variant: %-20s************************ comparison failed\n",$variant);
            if (open(IF,"$programDirectory/compareSimulationResults.pl $flag $error -c $clip -r $relTol -n $ndigit $refFile $simFile|")) {
                while (<IF>) {chomp;$message=$_;}
                close(IF);
            }
            print $message;
        } else {
            printf("     variant: %-20s************************ no results to compare to\n",$variant);
        }
    }
}
