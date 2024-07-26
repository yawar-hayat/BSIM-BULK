# Copyright (c) 2023 Silicon Integration Initiative, Inc., All rights reserved.
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
#   spectre DC, AC and noise test routines
#

#
#  Rel   Date            Who              Comments
#  ====  ==========      =============    ========
#  3.3.2 03/23/2023      Geoffrey Coram   Fix for operating-point information
#  3.3   08/31/2022      Shahriar Moinian Added initial results file cleanup
#  3.3   08/15/2022      Jushan Xie       Set minr=1e-3 as default 
#  3.1   02/23/2022      Geoffrey Coram   Removed unused variables
#  3.1   01/19/2022      Geoffrey Coram   Check keyLetter in generateCommonNetlistInfo
#  3.0   06/24/2021      Geoffrey Coram   Support tempSweep
#  2.2   10/04/2019      Geoffrey Coram   Move scale and shrink to the model card
#  2.1   07/27/2019      Geoffrey Coram   Improve detection of VA model card support
#  2.0   06/22/2017      Shahriar Moinian Added SI2 clauses
#        06/15/2017      Geoffrey Coram   Support OMI/TMI (preliminary)
#  1.11  11/28/2016      Geoffrey Coram   Allow testing of "expected failures"
#  1.9   12/12/2015      Geoffrey Coram   Support operating-point information
#                                         Cached detection of VA model card support
#  1.5   09/24/2014      Geoffrey Coram   Detect VA model card support
#                                         Improve clean-up
#  1.4   04/06/2011      Geoffrey Coram   Bug fix (noise)
#  1.3   06/21/2007      Colin McAndrew   Bug fixes
#  1.2   06/30/2006      Colin McAndrew   Floating node support added
#                                         Noise simulation added
#  1.0   04/13/2006      Colin McAndrew   Initial version
#

package simulate;
if (defined($main::simulatorCommand)) {
    $simulatorCommand=$main::simulatorCommand;
} else {
    $simulatorCommand="spectre";
}
$netlistFile="spectreCkt";
$dummyVaFile="cmcQaDummy.va";
$vaVersion="unknown";
$vaUseModelCard=0;
use strict;

sub version {
    my($version);
    $version="unknown";
    if (!open(OF,">$simulate::dummyVaFile")) {
        die("ERROR: cannot open file $simulate::dummyVaFile, stopped");
    }
    print OF "";
    print OF "`include \"discipline.h\"";
    print OF "`include \"constants.h\"";
    print OF "module dummy(p,n);";
    print OF "    inout      p,n;";
    print OF "    electrical p,n;";
    print OF "    (* type=\"instance\" *) parameter real ipar = 1;";
    print OF "    parameter real mpar = 1;";
    print OF "    analog begin";
    print OF "`ifdef P_Q_NIST2010";
    print OF "        \$strobe(\"Verilog-A version is: LRM2.4\");";
    print OF "`else";
    print OF "`ifdef __VAMS_COMPACT_MODELING__";
    print OF "        \$strobe(\"Verilog-A version is: LRM2.2\");";
    print OF "`else";
    print OF "        \$strobe(\"Verilog-A version is: LRM2.1\");";
    print OF "`endif";
    print OF "`endif";
    print OF "        if (mpar) begin";
    print OF "            \$strobe(\"Verilog-A model cards are supported.\");";
    print OF "        end";
    print OF "        I(p,n)  <+ V(p,n);";
    print OF "    end";
    print OF "endmodule";
    print OF "";
    close(OF);
    if (!open(OF,">$simulate::netlistFile")) {
        die("ERROR: cannot open file $simulate::netlistFile, stopped");
    }
    print OF "";
    print OF "simulator lang=spectre";
    print OF "";
    print OF "ahdl_include \"$simulate::dummyVaFile\"";
    print OF "";
    print OF "v1 (x 0) vsource dc=1";
    print OF "a1 (x 0) dummy mpar=0";
    print OF "";
    print OF "op info what=oppoint where=screen";
    print OF "";
    close(OF);
    if (!open(SIMULATE,"$simulate::simulatorCommand $simulate::netlistFile 2>/dev/null|")) {
        die("ERROR: cannot run $main::simulatorName, stopped");
    }
    while (<SIMULATE>) {
        chomp;
        s/\(/ /g;s/\)/ /g;
        if (s/^\s*(spectre\s+ver\.|version)\s+//i) {
            ($version=$_)=~s/\s+.*$//;
        }
        if (s/^\s*Verilog-A version is:\s*//i) {
            $simulate::vaVersion=$_;
        }
        if (/Verilog-A model cards are supported./) {
            $simulate::vaUseModelCard=1;
        }
    }
    close(SIMULATE);
    if (! $main::debug) {
        unlink($simulate::netlistFile);
        unlink($simulate::dummyVaFile);
#        system("/bin/rm -rf $simulate::dummyVaFile.dummy.ahdlcmi $simulate::netlistFile.ahdlSimDB");
        system("/bin/rm -rf $simulate::netlistFile.raw $simulate::netlistFile.log");
    }
    return($version,$simulate::vaVersion);
}

sub runNoiseTest {
    my($variant,$outputFile)=@_;
    my($i,$j,$k,$pin,$noisePin);
    my(@BiasList,@Field,$inData);
    my($temperature,$biasVoltage);
    my(@X,@Noise);

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
    if (!open(OF,">$simulate::netlistFile")) {
        die("ERROR: cannot open file $simulate::netlistFile, stopped");
    }
    print OF "\n// Noise simulation for $main::simulatorName\n";
    &generateCommonNetlistInfo($variant);
    @BiasList=split(/\s+/,$main::biasListSpec);
    foreach $pin (@main::Pin) {
        if ($main::isFloatingPin{$pin}) {
            print OF "i_$pin ($pin 0) isource dc=0";
            print OF "save $pin";
        } else {
            if (defined($main::referencePinFor{$pin})) {
                print OF "v_$pin ($pin ${pin}_$main::referencePinFor{$pin}) vsource dc=$main::BiasFor{$pin}";
                print OF "e_${pin} (${pin}_$main::referencePinFor{$pin} 0 $main::referencePinFor{$pin} 0) vcvs gain=1";
            } else {
                print OF "v_$pin ($pin 0) vsource dc=$main::BiasFor{$pin}";
            }
            print OF "save v_$pin:p";
        }
    }
    print OF "x1 (".join(" ",@main::Pin).") mysub";
    $noisePin=$main::Outputs[0];
    if ($main::outputNoise == 2) {
        $noisePin="($noisePin,$main::Outputs[1])";
    } elsif (! $main::isFloatingPin{$noisePin}) {
        print OF "fn (0 n_$noisePin) cccs probe=v_$noisePin gain=1";
        print OF "rn (0 n_$noisePin) resistor r=1 isnoisy=no";
        $noisePin="n_$noisePin";
    }
    if (defined($main::biasSweepSpec)) {
        for ($j=0;$j<=$#main::Temperature;++$j) {
            print OF "alterT$j alter param=temp value=$main::Temperature[$j]";
            for ($i=0;$i<=$#BiasList;++$i) {
                if ($main::biasListPin ne "dummyPinNameThatIsNeverUsed") {
                    print OF "alterT${j}_$i alter dev=v_$main::biasListPin param=dc value=$BiasList[$i]";
                }
                for ($k=0;$k<=$#main::BiasSweepList;++$k) {
                    if (!$main::isFloatingPin{$main::biasSweepPin} && $main::biasSweepPin ne "dummyPinNameThatIsNeverUsed") {
                        print OF "alterT${j}_${i}_$k alter dev=v_$main::biasSweepPin param=dc value=$main::BiasSweepList[$k]";
                    }
                    if ($main::fMin == $main::fMax) {
                        print OF "noise_t${j}_bl${i}_bs${k} $noisePin noise values=[$main::fMin]";
                    } else {
                        print OF "noise_t${j}_bl${i}_bs${k} $noisePin noise start=$main::fMin stop=$main::fMax $main::fType=$main::fSteps";
                    }
                }
            }
        }
    } elsif (defined($main::tempSweepSpec)) {
        for ($i=0;$i<=$#BiasList;++$i) {
            if ($main::biasListPin ne "dummyPinNameThatIsNeverUsed") {
                print OF "alter$i alter dev=v_$main::biasListPin param=dc value=$BiasList[$i]";
            }
            for ($k=0;$k<=$#main::TempSweepList;++$k) {
                if (!$main::isFloatingPin{$main::biasSweepPin} && $main::biasSweepPin ne "dummyPinNameThatIsNeverUsed") {
                    print OF "alter${i}_$k alter param=temp value=$main::TempSweepList[$k]";
                }
                if ($main::fMin == $main::fMax) {
                    print OF "noise_bl${i}_bs${k} $noisePin noise values=[$main::fMin]";
                } else {
                    print OF "noise_bl${i}_bs${k} $noisePin noise start=$main::fMin stop=$main::fMax $main::fType=$main::fSteps";
                }
            }
        }
    } else {
        die("ERROR: no sweep specification, stopped");
    }
    close(OF);

#
#   Run simulations and get the results
#

    if (!open(SIMULATE,"$simulate::simulatorCommand $simulate::netlistFile 2>/dev/null|")) {
        die("ERROR: cannot run $main::simulatorName, stopped");
    }
    while (<SIMULATE>) {
        chomp;
    }
    close(SIMULATE);
    if ($main::fMin == $main::fMax) {
        @X=();
        if (defined($main::biasSweepSpec)) {
            foreach $temperature (@main::Temperature) {
                foreach $biasVoltage (split(/\s+/,$main::biasListSpec)) {
                    push(@X,@main::BiasSweepList);
                }
            }
        } else {
            foreach $biasVoltage (split(/\s+/,$main::biasListSpec)) {
                push(@X,@main::TempSweepList);
            }
        }
    }
    if (defined($main::biasSweepSpec)) {
        for ($j=0;$j<=$#main::Temperature;++$j) {
            for ($i=0;$i<=$#BiasList;++$i) {
                for ($k=0;$k<=$#main::BiasSweepList;++$k) {
                    $inData=0;
                    if (! open(IF,"$simulate::netlistFile.raw/noise_t${j}_bl${i}_bs${k}.noise")) {
                        if (defined($main::expectError)) {
                            next;
                        } else {
                            die("ERROR: cannot open file noise_t${j}_bl${i}_bs${k}.noise, stopped");
                        }
                    }
                    while (<IF>) {
                        chomp;s/"//g;s/^\s+//;s/\s+$//;
                        @Field=split;
                        if (/VALUE/) {$inData=1}
                        next if (! $inData);
                        if (/^freq/ && ($main::fMin != $main::fMax)) {
                            push(@X,1*$Field[1]);
                        }
                        if (/^out/) {
                            push(@Noise,$Field[1]**2);
                        }
                    }
                    close(IF);
                }
            }
        }
    } else {
        for ($i=0;$i<=$#BiasList;++$i) {
            for ($k=0;$k<=$#main::TempSweepList;++$k) {
                $inData=0;
                if (! open(IF,"$simulate::netlistFile.raw/noise_bl${i}_bs${k}.noise")) {
                    if (defined($main::expectError)) {
                        next;
                    } else {
                        die("ERROR: cannot open file noise_bl${i}_bs${k}.noise, stopped");
                    }
                }
                while (<IF>) {
                    chomp;s/"//g;s/^\s+//;s/\s+$//;
                    @Field=split;
                    if (/VALUE/) {$inData=1}
                    next if (! $inData);
                    if (/^freq/ && ($main::fMin != $main::fMax)) {
                        push(@X,1*$Field[1]);
                    }
                    if (/^out/) {
                        push(@Noise,$Field[1]**2);
                    }
                }
                close(IF);
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
    if ($main::outputNoise == 2) {
        print OF (" N($main::Outputs[0],$main::Outputs[1])");
    } else {
        print OF (" N($main::Outputs[0])");
    }
    for ($i=0;$i<=$#X;++$i) {
        if (defined($Noise[$i])) {printf OF ("$X[$i] $Noise[$i]\n")}
    }
    close(OF);

#
#   Clean up, unless the debug flag was specified
#

    if (! $main::debug) {
        unlink($simulate::netlistFile);
#        if (defined($main::verilogaFile)) {
#            system("/bin/rm -rf $main::verilogaFile.*.ahdlcmi $simulate::netlistFile.ahdlSimDB");
#        }
        system("/bin/rm -rf $simulate::netlistFile.raw $simulate::netlistFile.log");
    }
}

sub runAcTest {
    my($variant,$outputFile)=@_;
    my($i,$j,$k,$type,$pin,$mPin,$fPin,$first_fPin);
    my(@BiasList,@Field,$inData);
    my($temperature,$biasVoltage);
    my(@X,$omega,%g,%c,%q,$twoPi,$outputLine);
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
    if (!open(OF,">$simulate::netlistFile")) {
        die("ERROR: cannot open file $simulate::netlistFile, stopped");
    }
    print OF "\n// AC simulation for $main::simulatorName\n";
    &generateCommonNetlistInfo($variant);
    @BiasList=split(/\s+/,$main::biasListSpec);
    foreach $pin (@main::Pin) {
        if ($main::isFloatingPin{$pin}) {
            print OF "i_$pin ($pin 0) isource dc=0";
            print OF "save $pin";
        } else {
            if (defined($main::referencePinFor{$pin})) {
                print OF "v_$pin ($pin ${pin}_$main::referencePinFor{$pin}) vsource dc=$main::BiasFor{$pin}";
                print OF "e_${pin} (${pin}_$main::referencePinFor{$pin} 0 $main::referencePinFor{$pin} 0) vcvs gain=1";
            } else {
                print OF "v_$pin ($pin 0) vsource dc=$main::BiasFor{$pin} mag=0";
            }
            print OF "save v_$pin:p";
        }
    }
    print OF "x1 (".join(" ",@main::Pin).") mysub";
    if (defined($main::biasSweepSpec)) {
        for ($j=0;$j<=$#main::Temperature;++$j) {
            print OF "alterT$j alter param=temp value=$main::Temperature[$j]";
            for ($i=0;$i<=$#BiasList;++$i) {
                if ($main::biasListPin ne "dummyPinNameThatIsNeverUsed") {
                    print OF "alterT${j}_$i alter dev=v_$main::biasListPin param=dc value=$BiasList[$i]";
                }
                for ($k=0;$k<=$#main::BiasSweepList;++$k) {
                    if ($main::biasSweepPin ne "dummyPinNameThatIsNeverUsed") {
                        print OF "alterT${j}_${i}_$k alter dev=v_$main::biasSweepPin param=dc value=$main::BiasSweepList[$k]";
                    }
                    foreach $pin (@main::Pin) {
                        next if (!$main::needAcStimulusFor{$pin});
                        print OF "setT${j}_${i}_${k}_$pin alter dev=v_$pin param=mag value=1";
                        if ($main::fMin == $main::fMax) {
                            print OF "acT${j}_${i}_${k}_$pin ac values=[$main::fMin]";
                        } else {
                            print OF "acT${j}_${i}_${k}_$pin ac start=$main::fMin stop=$main::fMax $main::fType=$main::fSteps";
                        }
                        print OF "unsetT${j}_${i}_${k}_$pin alter dev=v_$pin param=mag value=0";
                    }
                }
            }
        }
    } elsif (defined($main::tempSweepSpec)) {
        for ($i=0;$i<=$#BiasList;++$i) {
            if ($main::biasListPin ne "dummyPinNameThatIsNeverUsed") {
                print OF "alter$i alter dev=v_$main::biasListPin param=dc value=$BiasList[$i]";
            }
            for ($k=0;$k<=$#main::TempSweepList;++$k) {
                print OF "alter${i}_$k alter param=temp value=$main::TempSweepList[$k]";
                foreach $pin (@main::Pin) {
                    next if (!$main::needAcStimulusFor{$pin});
                    print OF "set${i}_${k}_$pin alter dev=v_$pin param=mag value=1";
                    if ($main::fMin == $main::fMax) {
                        print OF "ac${i}_${k}_$pin ac values=[$main::fMin]";
                    } else {
                        print OF "ac${i}_${k}_$pin ac start=$main::fMin stop=$main::fMax $main::fType=$main::fSteps";
                    }
                    print OF "unset${i}_${k}_$pin alter dev=v_$pin param=mag value=0";
                }
            }
        }
    } else {
        die("ERROR: no sweep specification, stopped");
    }
    close(OF);

#
#   Run simulations and get the results
#

    if (!open(SIMULATE,"$simulate::simulatorCommand $simulate::netlistFile 2>/dev/null|")) {
        die("ERROR: cannot run $main::simulatorName, stopped");
    }
    while (<SIMULATE>) {
        chomp;
    }
    close(SIMULATE);
    foreach $mPin (@main::Pin) {
        if ($main::needAcStimulusFor{$mPin} && !defined($first_fPin)) {$first_fPin=$mPin}
        foreach $fPin (@main::Pin) {
            @{$g{$mPin,$fPin}}=();
            @{$c{$mPin,$fPin}}=();
            @{$q{$mPin,$fPin}}=();
        }
    }
    if ($main::fMin == $main::fMax) {
        @X=();
        if (defined($main::biasSweepSpec)) {
            foreach $temperature (@main::Temperature) {
                foreach $biasVoltage (split(/\s+/,$main::biasListSpec)) {
                    push(@X,@main::BiasSweepList);
                }
            }
        } else {
            foreach $biasVoltage (split(/\s+/,$main::biasListSpec)) {
                push(@X,@main::TempSweepList);
            }
        }
    }
    $fPin=$main::Pin[0];
    if (defined($main::biasSweepSpec)) {
        for ($j=0;$j<=$#main::Temperature;++$j) {
            for ($i=0;$i<=$#BiasList;++$i) {
                for ($k=0;$k<=$#main::BiasSweepList;++$k) {
                    foreach $fPin (@main::Pin) {
                        next if (!$main::needAcStimulusFor{$fPin});
                        $inData=0;
                        if (! open(IF,"$simulate::netlistFile.raw/acT${j}_${i}_${k}_$fPin.ac")) {
                            if (defined($main::expectError)) {
                                next;
                            } else {
                                die("ERROR: cannot open file $simulate::netlistFile.raw/acT${j}_${i}_${k}_$fPin.ac, stopped");
                            }
                        }
                        while (<IF>) {
                            chomp;
                            if (/VALUE/) {$inData=1}
                            next if (! $inData);
                            s/\(/ /g;s/\)/ /g;s/"//g;s/:p//;s/^\s+//;s/\s+$//;
                            @Field=split;
                            if ($Field[0] eq "freq") {
                                $omega=$twoPi*$Field[1];
                                if (($main::fMin != $main::fMax) && ($fPin eq $first_fPin)) {
                                    push(@X,$Field[1]);
                                }
                            }
                            if ($Field[0] =~ /^v_/) {
                                $mPin=$';
                                push(@{$g{$mPin,$fPin}},-1*$Field[1]);
                                if ($mPin eq $fPin) {
                                    push(@{$c{$mPin,$fPin}},-1*$Field[2]/$omega);
                                } else {
                                    push(@{$c{$mPin,$fPin}},$Field[2]/$omega);
                                }
                                if (abs($Field[1]) > 1.0e-99) {
                                    push(@{$q{$mPin,$fPin}},$Field[2]/$Field[1]);
                                } else {
                                    push(@{$q{$mPin,$fPin}},1.0e99);
                                }
                            }
                        }
                        close(IF);
                    }
                }
            }
        }
    } else {
        for ($i=0;$i<=$#BiasList;++$i) {
            for ($k=0;$k<=$#main::TempSweepList;++$k) {
                foreach $fPin (@main::Pin) {
                    next if (!$main::needAcStimulusFor{$fPin});
                    $inData=0;
                    if (! open(IF,"$simulate::netlistFile.raw/ac${i}_${k}_$fPin.ac")) {
                        if (defined($main::expectError)) {
                            next;
                        } else {
                            die("ERROR: cannot open file $simulate::netlistFile.raw/ac${i}_${k}_$fPin.ac, stopped");
                        }
                    }
                    while (<IF>) {
                        chomp;
                        if (/VALUE/) {$inData=1}
                        next if (! $inData);
                        s/\(/ /g;s/\)/ /g;s/"//g;s/:p//;s/^\s+//;s/\s+$//;
                        @Field=split;
                        if ($Field[0] eq "freq") {
                            $omega=$twoPi*$Field[1];
                            if (($main::fMin != $main::fMax) && ($fPin eq $first_fPin)) {
                                push(@X,$Field[1]);
                            }
                        }
                        if ($Field[0] =~ /^v_/) {
                            $mPin=$';
                            push(@{$g{$mPin,$fPin}},-1*$Field[1]);
                            if ($mPin eq $fPin) {
                                push(@{$c{$mPin,$fPin}},-1*$Field[2]/$omega);
                            } else {
                                push(@{$c{$mPin,$fPin}},$Field[2]/$omega);
                            }
                            if (abs($Field[1]) > 1.0e-99) {
                                push(@{$q{$mPin,$fPin}},$Field[2]/$Field[1]);
                            } else {
                                push(@{$q{$mPin,$fPin}},1.0e99);
                            }
                        }
                    }
                    close(IF);
                }
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
#        if (defined($main::verilogaFile)) {
#            system("/bin/rm -rf $main::verilogaFile.*.ahdlcmi $simulate::netlistFile.ahdlSimDB");
#        }
        system("/bin/rm -rf $simulate::netlistFile.raw $simulate::netlistFile.log");
    }
}

sub runDcTest {
    my($variant,$outputFile)=@_;
    my($i,$j,$pin,@Field,$inData);
    my(@BiasList,$start,$stop,$step);
    my(@V,%DC);

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
#   One extra point is added at the beginning of the sweep,
#   as sometimes Spectre convergence is suspect for that point;
#   this is ignored when the results are returned.
#

    system("/bin/rm -rf $outputFile");
    if (!open(OF,">$simulate::netlistFile")) {
        die("ERROR: cannot open file $simulate::netlistFile, stopped");
    }
    print OF "\n// DC simulation for $main::simulatorName\n";
    &generateCommonNetlistInfo($variant);
    foreach $pin (@main::Pin) {
        if ($main::isFloatingPin{$pin}) {
            print OF "i_$pin ($pin 0) isource dc=0";
            print OF "save $pin";
        } else {
            if (defined($main::referencePinFor{$pin})) {
                print OF "v_$pin ($pin ${pin}_$main::referencePinFor{$pin}) vsource dc=$main::BiasFor{$pin}";
                print OF "e_${pin} (${pin}_$main::referencePinFor{$pin} 0 $main::referencePinFor{$pin} 0) vcvs gain=1";
            } else {
                print OF "v_$pin ($pin 0) vsource dc=$main::BiasFor{$pin}";
            }
            print OF "save v_$pin:p";
        }
    }
    if ($main::outputOp) {
        foreach $pin (@main::Outputs) {
            if ($pin =~ /^OP\((.*)\)/) {
                print OF "save x1.${main::keyLetter}1:$1";
            }
        }
    }
    print OF "x1 (".join(" ",@main::Pin).") mysub";
    @BiasList=split(/\s+/,$main::biasListSpec);
    if (defined($main::biasSweepSpec)) {
        ($start,$stop,$step)=split(/\s+/,$main::biasSweepSpec);
        $start-=$step;
        for ($j=0;$j<=$#main::Temperature;++$j) {
            print OF "alterT$j alter param=temp value=$main::Temperature[$j]";
            for ($i=0;$i<=$#BiasList;++$i) {
                if ($main::biasListPin ne "dummyPinNameThatIsNeverUsed") {
                    print OF "alterT${j}_$i alter dev=v_$main::biasListPin param=dc value=$BiasList[$i]";
                }
                print OF "dcT${j}_$i dc dev=v_$main::biasSweepPin start=$start stop=$stop step=$step";
            }
        }
    } elsif (defined($main::tempSweepSpec)) {
        ($start,$stop,$step)=split(/\s+/,$main::tempSweepSpec);
        $start-=$step;
        for ($i=0;$i<=$#BiasList;++$i) {
            if ($main::biasListPin ne "dummyPinNameThatIsNeverUsed") {
                print OF "alter$i alter dev=v_$main::biasListPin param=dc value=$BiasList[$i]";
            }
            print OF "dc_$i dc param=temp start=$start stop=$stop step=$step";
        }
    } else {
        die("ERROR: no sweep specification, stopped");
    }
    close(OF);

#
#   Run simulations and get the results
#

    if (!open(SIMULATE,"$simulate::simulatorCommand $simulate::netlistFile 2>/dev/null|")) {
        die("ERROR: cannot run $main::simulatorName, stopped");
    }
    while (<SIMULATE>) {
        chomp;
    }
    close(SIMULATE);
    @V=();
    foreach $pin (@main::Outputs) {
        if ($pin =~ /^OP\((.*)\)/) {
            @{$DC{$1}}=()
        } else {
            @{$DC{$pin}}=()
        }
    }
    if (defined($main::biasSweepSpec)) {
        for ($j=0;$j<=$#main::Temperature;++$j) {
            for ($i=0;$i<=$#BiasList;++$i) {
                $inData=0;
                if (! open(IF,"$simulate::netlistFile.raw/dcT${j}_$i.dc")) {
                    if (defined($main::expectError)) {
                        next;
                    } else {
                        die("ERROR: cannot open file $simulate::netlistFile.raw/dcT${j}_$i.dc, stopped");
                    }
                }
                while (<IF>) {
                    chomp;
                    if (/VALUE/) {$inData=1}
                    next if (! $inData);
                    s/"//g;s/:p\b//;s/^\s+//;s/\s+$//;
                    next if (/:p\b/);
                    @Field=split;
                    if ($Field[0] eq "dc") {push(@V,$Field[1]);next}
                    if ($Field[0] =~ /^x1\.${main::keyLetter}1:/) {push(@{$DC{$'}},$Field[1]);next}
                    if ($Field[0] =~ /^v_/) {push(@{$DC{$'}},-1*$Field[1]);next}
                    if ($main::isFloatingPin{$Field[0]}) {push(@{$DC{$Field[0]}},$Field[1]);next}
                }
                close(IF);
            }
        }
    } elsif (defined($main::tempSweepSpec)) {
        for ($i=0;$i<=$#BiasList;++$i) {
            $inData=0;
            if (! open(IF,"$simulate::netlistFile.raw/dc_$i.dc")) {
                if (defined($main::expectError)) {
                    next;
                } else {
                    die("ERROR: cannot open file $simulate::netlistFile.raw/dc_$i.dc, stopped");
                }
            }
            while (<IF>) {
                chomp;
                if (/VALUE/) {$inData=1}
                next if (! $inData);
                s/"//g;s/:p\b//;s/^\s+//;s/\s+$//;
                next if (/:p\b/);
                @Field=split;
                if ($Field[0] eq "temp") {push(@V,$Field[1]);next}
                if ($Field[0] =~ /^x1\.${main::keyLetter}1:/) {push(@{$DC{$'}},$Field[1]);next}
                if ($Field[0] =~ /^v_/) {push(@{$DC{$'}},-1*$Field[1]);next}
                if ($main::isFloatingPin{$Field[0]}) {push(@{$DC{$Field[0]}},$Field[1]);next}
            }
            close(IF);
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
        printf OF ("$V[$i]");
        foreach $pin (@main::Outputs) {
            if ($pin =~ /^OP\((.*)\)/) {
                printf OF (" ${$DC{$1}}[$i]");
            } else {
                printf OF (" ${$DC{$pin}}[$i]");
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
#        if (defined($main::verilogaFile)) {
#            system("/bin/rm -rf $main::verilogaFile.*.ahdlcmi $simulate::netlistFile.ahdlSimDB");
#        }
        system("/bin/rm -rf $simulate::netlistFile.raw $simulate::netlistFile.log");
    }
}

sub generateCommonNetlistInfo {
    my($variant)=$_[0];
    my(@Pin_x,$arg,$name,$value,$eFactor,$fFactor,$pin);
    if (!defined($main::keyLetter)) {
        $main::keyLetter = "x";
    }
    print OF "simulator lang=spectre insensitive=yes\n";
    print OF "printOptions options rawfmt=psfascii\n";
    if ($main::globalScaleFactor ne 1) {
        print OF "setScale options scalefactor=$main::globalScaleFactor";
    }
    if ($main::omiOption ne "") {
        print OF "omiOpt options $main::omiOption";
    }
    if ($simulate::vaVersion eq "LRM2.2") {
        if ($variant=~/^scale$/) {
            print OF "testOptions options scale=$main::scaleFactor";
        }
        if ($variant=~/^shrink$/) {
            print OF "testOptions options scale=".(1.0-$main::shrinkPercent*0.01);
        }
    }
    if (!$simulate::vaUseModelCard && -e "$main::resultsDirectory/vaUseModelCard") {
        # cached from previous run
        $simulate::vaUseModelCard=1;
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
        print OF "ahdl_include \"$main::verilogaFile\"";
    }
    foreach $pin (@main::Pin) {push(@Pin_x,"${pin}_x")}
    print OF "subckt mysub (".join(" ",@Pin_x).")";
    foreach $pin (@main::Pin) {
        if ($main::isFloatingPin{$pin}) {
            if ($main::outputNoise && $pin eq $main::Outputs[0]) {
                if ($variant=~/^m$/) {
                    $eFactor=sqrt($main::mFactor);
                } else {
                    $eFactor=1;
                }
                print OF "e_$pin (${pin}_x 0 ${pin} 0) vcvs gain=$eFactor";
            } else { # assumed "dt" thermal pin, no scaling sign change
                print OF "v_$pin (${pin} ${pin}_x) vsource dc=0";
            }
        } elsif ($variant=~/^Flip/ && defined($main::flipPin{$pin})) {
            print OF "e_$pin (${pin}   0 $main::flipPin{$pin}_x 0) vcvs gain=$eFactor";
            print OF "f_$pin ($main::flipPin{$pin}_x 0) cccs probe=e_$pin gain=$fFactor";
        } else {
            print OF "e_$pin (${pin}   0 ${pin}_x 0) vcvs gain=$eFactor";
            print OF "f_$pin (${pin}_x 0) cccs probe=e_$pin gain=$fFactor";
        }
    }
    my $ModelSelect="";
    if (!defined($main::verilogaFile) || $simulate::vaUseModelCard) {
        print OF "${main::keyLetter}1 (".join(" ",@main::Pin).") mymodel";
    } else {
        if ($variant=~/_P/) {
            print OF "${main::keyLetter}1 ".join(" ",@main::Pin)." $main::pTypeSelectionArguments";
            $ModelSelect="$main::pTypeSelectionArguments";
        } else {
            print OF "${main::keyLetter}1 ".join(" ",@main::Pin)." $main::nTypeSelectionArguments";
            $ModelSelect="$main::nTypeSelectionArguments";
        }
    }
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
    if (!defined($main::verilogaFile) || $simulate::vaUseModelCard) {
        if ($variant=~/_P/) {
            print OF "model mymodel $main::pTypeSelectionArguments";
            $ModelSelect="$main::pTypeSelectionArguments";
        } else {
            print OF "model mymodel $main::nTypeSelectionArguments";
            $ModelSelect="$main::nTypeSelectionArguments"; 
        }
    }
    if ($ModelSelect=~/^bsimimg/i) {
        print OF "+ minr=1e-3";
    }
    foreach $arg (@main::ModelParameters) {
        print OF "+ $arg";
    }
    if (defined($main::verilogaFile)) {
        if ($simulate::vaVersion ne "LRM2.2") {
            if ($variant=~/^scale$/) {
                print OF "+ scale=$main::scaleFactor";
            }
            if ($variant=~/^shrink$/) {
                print OF "+ shrink=$main::shrinkPercent";
            }
        }
    }
    print OF "ends";
}

1;
