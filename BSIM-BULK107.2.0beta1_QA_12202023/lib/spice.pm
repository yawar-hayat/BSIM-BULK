# Copyright (c) 2022 Silicon Integration Initiative, Inc., All rights reserved.
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
#   spice3f5 DC, AC and noise test routines
#

#
#  Rel  Date            Who              Comments
# ====  ==========      =============    ========
#  3.3  08/31/2022	Shahriar Moinian Added initial results file cleanup
#  3.1  02/23/2022      Geoffrey Coram   Removed unused variables
#  3.1  01/19/2022      Geoffrey Coram   Check keyLetter in generateCommonNetlistInfo
#  3.0  07/07/2021      Geoffrey Coram   Support tempSweep
#  2.0  06/22/17        Shahriar Moinian Added SI2 clauses
#       06/15/17        Geoffrey Coram   Error out on OMI/TMI
#  1.9  12/18/15        Geoffrey Coram   Support operating-point info
#                                        Bug fix
#  1.2  06/30/06        Colin McAndrew   Floating node support added
#                                        Noise simulation added
#  1.0  04/13/06        Colin McAndrew   Initial version
#

package simulate;
if (defined($main::simulatorCommand)) {
    $simulatorCommand=$main::simulatorCommand;
} else {
    $simulatorCommand="spice3f5";
}
$netlistFile="spiceCkt";
use strict;

sub version {
    return("3f5","none"); # the version only seems to be printed in interactive mode
}

sub runNoiseTest {
    my($variant,$outputFile)=@_;
    my($pin,$noisePin);
    my(@TempList,@SweepList,$i,@Field);
    my(@X,@Noise,$temperature,$biasVoltage,$sweepVoltage,$sweepValue,$inData);

#
#   Make up the netlist, using a subckt to encapsulate the
#   instance. This simplifies handling of the variants as
#   the actual instance is driven by voltage-controlled
#   voltage sources from the subckt pins, and the currents
#   are fed back to the subckt pins using current-controlled
#   current sources. Pin swapping, polarity reversal, and
#   m-factor scaling can all be handled by simple modifications
#   of this subckt.
#

    system("/bin/rm -rf $outputFile");
    @X=();@Noise=();
    $noisePin=$main::Outputs[0];
    if ($main::fMin == $main::fMax) {
        $main::frequencySpec="lin 0 $main::fMin ".(10*$main::fMin); # spice3f5 bug workaround
    }
    if (defined($main::biasSweepSpec)) {
        @TempList = @main::Temperature;
        @SweepList = @main::BiasSweepList;
    } elsif (defined($main::tempSweepSpec)) {
        @TempList = $main::Temperature[0];
        @SweepList = @main::TempSweepList;
    } else {
        die("ERROR: no sweep specification, stopped");
    }
    foreach $temperature (@TempList) {
        foreach $biasVoltage (split(/\s+/,$main::biasListSpec)) {
            if ($main::fMin == $main::fMax) {
                if (defined($main::biasSweepSpec)) {
                    push(@X,@main::BiasSweepList);
                } else {
                    push(@X,@main::TempSweepList);
                }
            }
            foreach $sweepValue (@SweepList) {
               if (defined($main::biasSweepSpec)) {
                    $sweepVoltage = $sweepValue;
                } else {
                    $sweepVoltage = 0;
                    $temperature = $sweepValue;
                }
                if (!open(OF,">$simulate::netlistFile")) {
                    die("ERROR: cannot open file $simulate::netlistFile, stopped");
                }
                print OF "* Noise simulation for $main::simulatorName";
                &generateCommonNetlistInfo($variant,$temperature);
                print OF "vin dummy 0 0 ac 1";
                print OF "rin dummy 0 1";
                foreach $pin (@main::Pin) {
                    if ($main::isFloatingPin{$pin}) {
                        print OF "i_$pin $pin 0 0";
                    } elsif ($pin eq $main::biasListPin) {
                        if (defined($main::referencePinFor{$pin})) {
                            print OF "v_${pin} ${pin} ${pin}_$main::referencePinFor{$pin} $biasVoltage";
                            print OF "e_${pin} ${pin}_$main::referencePinFor{$pin} 0 $main::referencePinFor{$pin} 0 1";
                        } else {
                            print OF "v_$pin $pin 0 $biasVoltage";
                        }
                    } elsif ($pin eq $main::biasSweepPin) {
                        if (defined($main::referencePinFor{$pin})) {
                            print OF "v_${pin} ${pin} ${pin}_$main::referencePinFor{$pin} $sweepVoltage";
                            print OF "e_${pin} ${pin}_$main::referencePinFor{$pin} 0 $main::referencePinFor{$pin} 0 1";
                        } else {
                            print OF "v_$pin $pin 0 $sweepVoltage";
                        }
                    } else {
                        if (defined($main::referencePinFor{$pin})) {
                            print OF "v_${pin} ${pin} ${pin}_$main::referencePinFor{$pin} $main::BiasFor{$pin}";
                            print OF "e_${pin} ${pin}_$main::referencePinFor{$pin} 0 $main::referencePinFor{$pin} 0 1";
                        } else {
                            print OF "v_${pin} ${pin} 0 $main::BiasFor{$pin}";
                        }
                    }
                }
                if ($main::isFloatingPin{$noisePin}) {
                    print OF ".noise v($noisePin) vin $main::frequencySpec";
                } else {
                    print OF "x1 ".join(" ",@main::Pin)." mysub";
                    print OF "hn 0 n_$noisePin v_$noisePin 1";
                    print OF ".noise v(n_$noisePin) vin $main::frequencySpec";
                }
                print OF ".print noise all";
                print OF ".end";
                close(OF);
        
#
#   Run simulations and get the results
#

                if (!open(SIMULATE,"$simulate::simulatorCommand < $simulate::netlistFile 2>/dev/null|")) {
                    die("ERROR: cannot run $main::simulatorName, stopped");
                }
                $inData=0;
                while (<SIMULATE>) {
                    chomp;s/^\s+//;s/\s+$//;s/,/ /g;
                    if (/Index\s+frequency\s+inoise_spectrum\s+onoise_spectrum/i) {
                        $inData=1;<SIMULATE>;next;
                    }
                    @Field=split;
                    if (/\*/ || ($#Field != 3)) {$inData=0}
                    next if (!$inData);
                    if ($main::fMin == $main::fMax) {
                        push(@Noise,1*$Field[3]);$inData=0;next; # spice3f5 bug workaround
                    }
                    push(@X,1*$Field[1]);
                    push(@Noise,1*$Field[3]);
                }
                close(SIMULATE);
            }
        }
    }

#
#   Write the results to a file
#

    if (!open(OF,">$outputFile")) {
        die("ERROR: cannot open file $outputFile, stopped");
    }
    if ($main::fMin == $main::fMax) {
        if (defined($main::biasSweepSpec)) {
            printf OF ("V($main::biasSweepPin)");
        } else {
            printf OF ("Temp");
        }
    } else {
        printf OF ("Freq");
    }
    foreach (@main::Outputs) {
        printf OF (" N($_)");
    }
    printf OF ("\n");
    for ($i=0;$i<=$#X;++$i) {
        if (defined($Noise[$i])) {printf OF ("$X[$i] $Noise[$i]\n")}
    }
    close(OF);

#
#   Clean up, unless the debug flag was specified
#

    if (! $main::debug) {
        unlink($simulate::netlistFile);
        unlink("$simulate::netlistFile.st0");
        if (!opendir(DIRQA,".")) {
            die("ERROR: cannot open directory ., stopped");
        }
        foreach (grep(/^$simulate::netlistFile\.ic/,readdir(DIRQA))) {unlink($_)}
        closedir(DIRQA);
    }
}

sub runAcTest {
    my($variant,$outputFile)=@_;
    my($type,$mPin,$fPin,$first_fPin);
    my(@TempList,@SweepList,$acStim,$i,@Field);
    my(@X,$omega,$twoPi,%g,%c,%q,$temperature,$biasVoltage,$sweepVoltage,$sweepValue,$inData,$outputLine);
    $twoPi=8.0*atan2(1.0,1.0);

#
#   Make up the netlist, using a subckt to encapsulate the
#   instance. This simplifies handling of the variants as
#   the actual instance is driven by voltage-controlled
#   voltage sources from the subckt pins, and the currents
#   are fed back to the subckt pins using current-controlled
#   current sources. Pin swapping, polarity reversal, and
#   m-factor scaling can all be handled by simple modifications
#   of this subckt.
#

    system("/bin/rm -rf $outputFile");
    foreach $mPin (@main::Pin) {
        if ($main::needAcStimulusFor{$mPin} && !defined($first_fPin)) {$first_fPin=$mPin}
        foreach $fPin (@main::Pin) {
            @{$g{$mPin,$fPin}}=();
            @{$c{$mPin,$fPin}}=();
            @{$q{$mPin,$fPin}}=();
        }
    }
    @X=();

    if (defined($main::biasSweepSpec)) {
        @TempList = @main::Temperature;
        @SweepList = @main::BiasSweepList;
    } elsif (defined($main::tempSweepSpec)) {
        @TempList = $main::Temperature[0];
        @SweepList = @main::TempSweepList;
    } else {
        die("ERROR: no sweep specification, stopped");
    }
    foreach $temperature (@TempList) {
        foreach $biasVoltage (split(/\s+/,$main::biasListSpec)) {
            if ($main::fMin == $main::fMax) {
                if (defined($main::biasSweepSpec)) {
                    push(@X,@main::BiasSweepList);
                } else {
                    push(@X,@main::TempSweepList);
                }
            }
            foreach $sweepValue (@SweepList) {
                if (defined($main::biasSweepSpec)) {
                    $sweepVoltage = $sweepValue;
                } else {
                    $sweepVoltage = 0;
                    $temperature = $sweepValue;
                }
                if (!open(OF,">$simulate::netlistFile")) {
                    die("ERROR: cannot open file $simulate::netlistFile, stopped");
                }
                print OF "* AC simulation for $main::simulatorName";
                &generateCommonNetlistInfo($variant,$temperature);
                foreach $fPin (@main::Pin) {
                    next if (!$main::needAcStimulusFor{$fPin});
                    foreach $mPin (@main::Pin) {
                        if ($mPin eq $fPin) {
                            $acStim=" ac 1";
                        } else {
                            $acStim="";
                        }
                        if ($main::isFloatingPin{$mPin}) {
                            print OF "i_${mPin}_$fPin ${mPin}_$fPin 0 0";
                        } elsif ($mPin eq $main::biasListPin) {
                            if (defined($main::referencePinFor{$mPin})) {
                                print OF "v_${mPin}_$fPin ${mPin}_$fPin ${mPin}_${fPin}_$main::referencePinFor{$mPin} $biasVoltage$acStim";
                                print OF "e_${mPin}_$fPin ${mPin}_${fPin}_$main::referencePinFor{$mPin} 0 $main::referencePinFor{$mPin}_$fPin 0 1";
                            } else {
                                print OF "v_${mPin}_$fPin ${mPin}_$fPin 0 $biasVoltage$acStim";
                            }
                        } elsif ($mPin eq $main::biasSweepPin) {
                            if (defined($main::referencePinFor{$mPin})) {
                                print OF "v_${mPin}_$fPin ${mPin}_$fPin ${mPin}_${fPin}_$main::referencePinFor{$mPin} $sweepVoltage$acStim";
                                print OF "e_${mPin}_$fPin ${mPin}_${fPin}_$main::referencePinFor{$mPin} 0 $main::referencePinFor{$mPin}_$fPin 0 1";
                            } else {
                                print OF "v_${mPin}_$fPin ${mPin}_$fPin 0 $sweepVoltage$acStim";
                            }
                        } else {
                            if (defined($main::referencePinFor{$mPin})) {
                                print OF "v_${mPin}_$fPin ${mPin}_$fPin ${mPin}_${fPin}_$main::referencePinFor{$mPin} $main::BiasFor{$mPin}$acStim";
                                print OF "e_${mPin}_$fPin ${mPin}_${fPin}_$main::referencePinFor{$mPin} 0 $main::referencePinFor{$mPin}_$fPin 0 1";
                            } else {
                                print OF "v_${mPin}_$fPin ${mPin}_$fPin 0 $main::BiasFor{$mPin}$acStim";
                            }
                        }
                    }
                    print OF "x_$fPin ".join("_$fPin ",@main::Pin)."_$fPin mysub";
                }
                print OF ".ac $main::frequencySpec";
                foreach $fPin (@main::Pin) {
                    next if (!$main::needAcStimulusFor{$fPin});
                    foreach $mPin (@main::Pin) {
                        print OF ".print ac i(v_${mPin}_$fPin)";
                    }
                }
                print OF ".end";
                close(OF);
        
#
#   Run simulations and get the results
#

                if (!open(SIMULATE,"$simulate::simulatorCommand < $simulate::netlistFile 2>/dev/null|")) {
                    die("ERROR: cannot run $main::simulatorName, stopped");
                }
                $inData=0;
                while (<SIMULATE>) {
                    chomp;s/^\s+//;s/\s+$//;s/,/ /g;
                    if (/^Index\s+frequency\s+v_([a-zA-z][a-zA-Z0-9]*)_([a-zA-z][a-zA-Z0-9]*)#branch/i) {
                        $mPin=$1;$fPin=$2;<SIMULATE>;$inData=1;next;
                    }
                    @Field=split;
                    if (/^\*/ || ($#Field != 4)) {$inData=0}
                    next if (!$inData);
                    if (($main::fMin != $main::fMax) && ($mPin eq $fPin) && ($mPin eq $first_fPin)) {
                        push(@X,1*$Field[1]);
                    }
                    push(@{$g{$mPin,$fPin}},$Field[3]);
                    $omega=$twoPi*$Field[1];
                    if ($mPin eq $fPin) {
                        push(@{$c{$mPin,$fPin}},$Field[4]/$omega);
                    } else {
                        push(@{$c{$mPin,$fPin}},-1*$Field[4]/$omega);
                    }
                    if (abs($Field[3]) > 1.0e-99) {
                        push(@{$q{$mPin,$fPin}},$Field[4]/$Field[3]);
                    } else {
                        push(@{$q{$mPin,$fPin}},1.0e99);
                    }
                }
                close(SIMULATE);
            }
        }
    }

#
#   Write the results to a file
#

    if (!open(OF,">$outputFile")) {
        die("ERROR: cannot open file $outputFile, stopped");
    }
    if ($main::fMin == $main::fMax) {
        if (defined($main::biasSweepSpec)) {
            printf OF ("V($main::biasSweepPin)");
        } else {
            printf OF ("Temp");
        }
    } else {
        printf OF ("Freq");
    }
    foreach (@main::Outputs) {
        ($type,$mPin,$fPin)=split(/\s+/,$_);
        printf OF (" $type($mPin,$fPin)");
    }
    printf OF ("\n");
    for ($i=0;$i<=$#X;++$i) {
        $outputLine="$X[$i]";
        foreach (@main::Outputs) {
            ($type,$mPin,$fPin)=split(/\s+/,$_);
            if ($type eq "g") {
                if (defined(${$g{$mPin,$fPin}}[$i])) {
                    $outputLine.=" ${$g{$mPin,$fPin}}[$i]";
                } else {
                    undef($outputLine);last;
                }
            } elsif ($type eq "c") {
                if (defined(${$c{$mPin,$fPin}}[$i])) {
                    $outputLine.=" ${$c{$mPin,$fPin}}[$i]";
                } else {
                    undef($outputLine);last;
                }
            } else {
                if (defined(${$q{$mPin,$fPin}}[$i])) {
                    $outputLine.=" ${$q{$mPin,$fPin}}[$i]";
                } else {
                    undef($outputLine);last;
                }
            }
        }
        if (defined($outputLine)) {printf OF ("$outputLine\n")}
    }
    close(OF);

#
#   Clean up, unless the debug flag was specified
#

    if (! $main::debug) {
        unlink($simulate::netlistFile);
        unlink("$simulate::netlistFile.st0");
        if (!opendir(DIRQA,".")) {
            die("ERROR: cannot open directory ., stopped");
        }
        foreach (grep(/^$simulate::netlistFile\.ic/,readdir(DIRQA))) {unlink($_)}
        closedir(DIRQA);
    }
}

sub runDcTest {
    my($variant,$outputFile)=@_;
    my($i,@Field,$pin);
    my($start,$stop,$step);
    my(@V,%DC,$temperature,@TempList,$biasVoltage);
    my($inResults);

#
#   Make up the netlist, using a subckt to encapsulate the
#   instance. This simplifies handling of the variants as
#   the actual instance is driven by voltage-controlled
#   voltage sources from the subckt pins, and the currents
#   are fed back to the subckt pins using current-controlled
#   current sources. Pin swapping, polarity reversal, and
#   m-factor scaling can all be handled by simple modifications
#   of this subckt.
#

    system("/bin/rm -rf $outputFile");
    @V=();
    foreach $pin (@main::Outputs) {
        if ($pin =~ /^OP\((.*)\)/) {
            @{$DC{$1}}=()
        } else {
            @{$DC{$pin}}=()
        }
    }

    if (defined($main::biasSweepSpec)) {
        ($start,$stop,$step)=split(/\s+/,$main::biasSweepSpec);
        $start-=$step;
        @TempList = @main::Temperature;
    } elsif (defined($main::tempSweepSpec)) {
        ($start,$stop,$step)=split(/\s+/,$main::tempSweepSpec);
        $start-=$step;
        @TempList = @main::TempSweepList;
    } else {
        die("ERROR: no sweep specification, stopped");
    }

    foreach $temperature (@TempList) {
        foreach $biasVoltage (split(/\s+/,$main::biasListSpec)) {
            if (!open(OF,">$simulate::netlistFile")) {
                die("ERROR: cannot open file $simulate::netlistFile, stopped");
            }
            print OF "* DC simulation for $main::simulatorName";
            &generateCommonNetlistInfo($variant,$temperature);
            foreach $pin (@main::Pin) {
                if ($main::isFloatingPin{$pin}) {
                    print OF "i_$pin $pin 0 0";
                } elsif ($pin eq $main::biasListPin) {
                    if (defined($main::referencePinFor{$pin})) {
                        print OF "v_${pin} ${pin} ${pin}_$main::referencePinFor{$pin} $biasVoltage";
                        print OF "e_${pin} ${pin}_$main::referencePinFor{$pin} 0 $main::referencePinFor{$pin} 0 1";
                    } else {
                        print OF "v_$pin $pin 0 $biasVoltage";
                    }
                } elsif ($pin eq $main::biasSweepPin) {
                    if (defined($main::referencePinFor{$pin})) {
                        print OF "v_${pin} ${pin} ${pin}_$main::referencePinFor{$pin} $start";
                        print OF "e_${pin} ${pin}_$main::referencePinFor{$pin} 0 $main::referencePinFor{$pin} 0 1";
                    } else {
                        print OF "v_$pin $pin 0 $start";
                    }
                } else {
                    if (defined($main::referencePinFor{$pin})) {
                        print OF "v_${pin} ${pin} ${pin}_$main::referencePinFor{$pin} $main::BiasFor{$pin}";
                        print OF "e_${pin} ${pin}_$main::referencePinFor{$pin} 0 $main::referencePinFor{$pin} 0 1";
                    } else {
                        print OF "v_${pin} ${pin} 0 $main::BiasFor{$pin}";
                    }
                }
            }
            print OF "x1 ".join(" ",@main::Pin)." mysub";
            if (defined($main::biasSweepSpec)) {
                print OF ".dc v_$main::biasSweepPin $main::biasSweepSpec";
            } else {
                print OF "v_dummy_temp dummy_temp 0 $temperature";
                print OF ".dc v_dummy_temp $temperature $temperature 1";
            }
            foreach $pin (@main::Outputs) {
                if ($pin =~ /^OP\((.*)\)/) {
                    print OF ".print dc \@${main::keyLetter}:1:1\[$1\]"
                } elsif ($main::isFloatingPin{$pin}) {
                    print OF ".print dc v($pin)";
                } else {
                    print OF ".print dc i(v_$pin)";
                }
            }
            print OF ".end";
            close(OF);
        
#
#   Run simulations and get the results
#

            if (!open(SIMULATE,"$simulate::simulatorCommand < $simulate::netlistFile 2>/dev/null|")) {
                die("ERROR: cannot run $main::simulatorName, stopped");
            }
            $inResults=0;
            while (<SIMULATE>) {
                chomp;s/^\s+//;s/\s+$//;s/#branch//;s/\(/_/;s/\)//;
                if (/^Index\s+sweep\s+v_(.*)/i) {$inResults=1;($pin=$1);<SIMULATE>;next}
                if (/^Index\s+sweep\s+\@${main::keyLetter}:1:1\[(.*)\]/i) {$inResults=1;($pin=$1);<SIMULATE>;next}
                @Field=split;
                if ($#Field != 2) {$inResults=0}
                next if (!$inResults);
                if ($pin eq $main::Outputs[0]) {
                    push(@V,$Field[1]);
                }
                push(@{$DC{$pin}},$Field[2]);
            }
            close(SIMULATE);
        }
    }

#
#   Write the results to a file
#

    if (!open(OF,">$outputFile")) {
        die("ERROR: cannot open file $outputFile, stopped");
    }
    if (defined($main::biasSweepSpec)) {
        printf OF ("V($main::biasSweepPin)");
    } else {
        printf OF ("Temp");
    }
    foreach $pin (@main::Outputs) {
        if ($pin =~ /^OP/) {
            printf OF (" $pin");
        } elsif ($main::isFloatingPin{$pin}) {
            printf OF (" V($pin)");
        } else {
            printf OF (" I($pin)");
        }
    }
    printf OF ("\n");
    for ($i=0;$i<=$#V;++$i) {
        next if (abs($V[$i]-$start) < abs(0.1*$step)); # this is dummy first bias point
        next if ($i > 0 && abs($V[$i]-$V[$i-1]) < abs(0.1*$step)); # this is duplicate point
        printf OF ("$V[$i]");
        foreach $pin (@main::Outputs) {
            if ($pin =~ /^OP\((.*)\)/) {
                printf OF (" ${$DC{$1}}[$i]")
            } else {
                printf OF (" ${$DC{$pin}}[$i]")
            }
        }
        printf OF ("\n");
    }
    close(OF);

#
#   Clean up, unless the debug flag was specified
#

    if (! $main::debug) {
        unlink($simulate::netlistFile);
        unlink("$simulate::netlistFile.st0");
        if (!opendir(DIRQA,".")) {
            die("ERROR: cannot open directory ., stopped");
        }
        foreach (grep(/^$simulate::netlistFile\.ic/,readdir(DIRQA))) {unlink($_)}
        closedir(DIRQA);
    }
}

sub generateCommonNetlistInfo {
    my($variant,$temperature)=@_;
    my(@Pin_x,$arg,$name,$value,$eFactor,$fFactor,$pin);
    if (!defined($main::keyLetter)) {
        die("ERROR: no keyLetter specified, stopped");
    }
    foreach $pin (@main::Pin) {push(@Pin_x,"${pin}_x")}
    print OF ".options temp=$temperature";
    if ($main::globalScaleFactor ne 1) {
        die("ERROR: there is no scale or shrink option for spice, stopped");
    }
    if ($main::omiOption ne "") {
        die("ERROR: OMI is not supported for spice, stopped");
    }
    if ($variant=~/^scale$/) {
        die("ERROR: there is no scale or shrink option for spice, stopped");
    }
    if ($variant=~/^shrink$/) {
        die("ERROR: there is no scale or shrink option for spice, stopped");
    }
    if ($variant=~/_P/) {
        $eFactor=-1;$fFactor=1;
    } else {
        $eFactor=1;$fFactor=-1;
    }
    if ($variant=~/^m$/) {
        if ($main::outputNoise) {
            $fFactor/=sqrt($main::mFactor);
        } else {
            $fFactor/=$main::mFactor;
        }
    }
    if (defined($main::verilogaFile)) {
        die("ERROR: Verilog-A model support is not implemented for spice, stopped");
    }
    print OF ".subckt mysub ".join(" ",@Pin_x);
    foreach $pin (@main::Pin) {
        if ($main::isFloatingPin{$pin}) {
            if ($main::outputNoise && $pin eq $main::Outputs[0]) {
                if ($variant=~/^m$/) {
                    $eFactor=sqrt($main::mFactor);
                } else {
                    $eFactor=1;
                }
                print OF "e_$pin ${pin}_x 0 ${pin} 0 $eFactor";
            } else { # assumed "dt" thermal pin, no scaling sign change
                print OF "v_$pin ${pin} ${pin}_x 0";
            }
        } elsif ($variant=~/^Flip/ && defined($main::flipPin{$pin})) {
            print OF "e_$pin ${pin}_v 0 $main::flipPin{$pin}_x 0 $eFactor";
            print OF "v_$pin ${pin}_v ${pin} 0";
            print OF "f_$pin $main::flipPin{$pin}_x 0 v_$pin   $fFactor";
        } else {
            print OF "e_$pin ${pin}_v 0 ${pin}_x 0 $eFactor";
            print OF "v_$pin ${pin}_v ${pin} 0";
            print OF "f_$pin ${pin}_x 0 v_$pin   $fFactor";
        }
    }
    print OF "${main::keyLetter}1 ".join(" ",@main::Pin)." mymodel";
    foreach $arg (@main::InstanceParameters) {
        ($name,$value)=split(/=/,$arg);
        if ($variant=~/^scale$/) {
            if ($main::isLinearScale{$name}) {
                $value/=$main::scaleFactor;
            } elsif ($main::isAreaScale{$name}) {
                $value/=$main::scaleFactor**2;
            }
        }
        if ($variant=~/^shrink$/) {
            if ($main::isLinearScale{$name}) {
                $value/=(1.0-$main::shrinkPercent*0.01);
            } elsif ($main::isAreaScale{$name}) {
                $value/=(1.0-$main::shrinkPercent*0.01)**2;
            }
        }
        print OF "+ $name=$value";
    }
    if ($variant eq "m") {
        print OF "+ m=$main::mFactor";
    }
    if ($variant=~/_P/) {
        print OF ".model mymodel $main::pTypeSelectionArguments";
    } else {
        print OF ".model mymodel $main::nTypeSelectionArguments";
    }
    foreach $arg (@main::ModelParameters) {
        print OF "+ $arg";
    }
    print OF ".ends";
}

1;
