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
#   eldo DC, AC and noise test routines
#

#
#  Rel   Date         Who                Comments
# =====  ==========   =============      ========
#  3.3   08/31/2022   Shahriar Moinian   Added initial results file cleanup
#  3.3   06/21/2022   Ahmed Abo-Elhadid  Removed gmin=1e-15 setting
#  3.2   04/12/2022   Geoffrey Coram     Don't print currents of floating pins
#  3.1   02/23/2022   Geoffrey Coram     Removed unused variables
#  3.1   01/19/2022   Geoffrey Coram     Check keyLetter in generateCommonNetlistInfo
#                                        Fix operating-point support
#  2.5   06/30/2021   Geoffrey Coram/    Support tempSweep
#                     Mohamed Ismail
#  2.0   06/22/2017   Shahriar Moinian   Added SI2 clauses
#        06/15/2017   Geoffrey Coram     Support OMI/TMI (preliminary)
#  1.12  04/26/2017   Geoffrey Coram     Support noise voltage
#  1.9   12/12/2015   Geoffrey Coram     Support operating-point information
#  1.7   09/24/2014   Geoffrey Coram     Verilog-A version detection added
#                                        Improve clean-up
#  1.4   04/06/2011   Geoffrey Coram     Fixed version detection; fixed ac-freq result printing
#  1.0   06/21/2007   Yousry Elmaghraby  Initial release
#                     Rob Jones          for modelQa release 1.3
# IS : BUG fix in 1) runNoiseTest for single frequency 
#                 2) runDcTest for extra SH node voltage plotting

package simulate;
if (defined($main::simulatorCommand)) {
    $simulatorCommand=$main::simulatorCommand;
} else {
    $simulatorCommand="eldo";
}
$netlistFile="eldoCkt";
$dummyVaFile="cmcQaDummy.va";
use strict;

sub version {
    my($version,$vaVersion);
    $version="";
    $vaVersion="";
#    if ($main::simulatorCommand_eldo eq "null")
#    {
      if (!open(SIMULATOR, "simulator")) {
        #printf ("Warning: File simulator Not Found, using the default eldo");
        $simulate::simulatorCommand = "eldo";
      }
      else {
        while (<SIMULATOR>) {
          chomp;
          if(s/^simulatorCommand\s+//i){
            $simulate::simulatorCommand = $_;
          }
        }
      }
    if (!open(OF,">$simulate::dummyVaFile")) {
        die("ERROR: cannot open file $simulate::dummyVaFile, stopped");
    }
    print OF "";
    print OF "`include \"discipline.h\"";
    print OF "module dummy(p,n);";
    print OF "    inout      p,n;";
    print OF "    electrical p,n;";
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
    print OF "        I(p,n)  <+ V(p,n);";
    print OF "    end";
    print OF "endmodule";
    print OF "";
    close(OF);
    if (!open(OF,">$simulate::netlistFile")) {
        die("ERROR: cannot open file $simulate::netlistFile, stopped");
    }
    print OF "";
    print OF ".hdl \"$simulate::dummyVaFile\"";
    print OF "x1 1 0 dummy";
    print OF "v1 1 0 1";
    print OF ".op";
    print OF ".end";
    close(OF);
    if (!open(SIMULATE,"$simulate::simulatorCommand -v 2>/dev/null|")) {
        die("ERROR: cannot run $main::simulatorName, stopped");
    }
    while (<SIMULATE>) {
        chomp;
        if (/^Eldo\s+VERSION\s*:\s*ELDO\s+(\S+)\s+/) {
            if ($version eq "" ) {
                $version=$1;
                $vaVersion="";
            }
        }
        if (s/^\s*Verilog-A version is:\s*//i) {
            $vaVersion=$_;
        }
    }
    close(SIMULATE);
    if (! $main::debug) {
        unlink($simulate::netlistFile);
        unlink("$simulate::netlistFile.st0");
        unlink($simulate::dummyVaFile);
        unlink("$simulate::netlistFile.val");
        unlink("$simulate::netlistFile.valog");
        system("/bin/rm -rf $simulate::netlistFile.pvadir");
        if (!opendir(DIRQA,".")) {
            die("ERROR: cannot open directory ., stopped");
        }
        foreach (grep(/^$simulate::netlistFile\.ic/,readdir(DIRQA))) {unlink($_)}
        closedir(DIRQA);
        unlink("hspice.errors");
        unlink("simout.tmp");
    }
    return($version, $vaVersion);
}

sub runNoiseTest {
    my($variant,$outputFile)=@_;
    my($pin,$noisePin);
    my(@TempList,@SweepList,$i,@Field,$old_freq);
    my(@X,@Noise,$temperature,$biasVoltage,$sweepVoltage,$sweepValue,$inData);
    my($cirFile,$resultsDirectory,$test,$circuitsDirectory);
    $circuitsDirectory="$main::resultsDirectory/circuits";
    if (! -d $circuitsDirectory) {mkdir($circuitsDirectory,0775)}
    $resultsDirectory=$main::resultsDirectory;
    $test=$main::test;
    $cirFile="$resultsDirectory/circuits/$test.$variant.cir";
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
    if (defined($main::biasSweepSpec)) {
        @TempList = @main::Temperature;
        @SweepList = @main::BiasSweepList;
    } elsif (defined($main::tempSweepSpec)) {
        @TempList = $main::Temperature[0];
        @SweepList = @main::TempSweepList;
    } else {
        die("ERROR: no sweep specification, stopped");
    }

    if (!open(OF,">$simulate::netlistFile")) {
        die("ERROR: cannot open file $simulate::netlistFile, stopped");
    }
    print OF "* Noise simulation for $main::simulatorName";
    &generateCommonNetlistInfo($variant);
    print OF "vin dummy 0 0 ac 1";
    print OF "rin dummy 0 rmod";
    print OF ".model rmod r res=1 noise=0"; #changed from rdef to res due to hspice compatibility since AM removed -compat from cmc scribt so we has to match it now uing res instead of rdef

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
                print OF ".alter";
                print OF ".temp $temperature";
                foreach $pin (@main::Pin) {
                    if ($main::isFloatingPin{$pin}) {
                        print OF "i_$pin $pin 0 0";
                    } elsif ($pin eq $main::biasListPin) {
                        print OF "v_$pin $pin 0 $biasVoltage";
                    } elsif ($pin eq $main::biasSweepPin) {
                        print OF "v_$pin $pin 0 $sweepVoltage";
                    } else {
                        print OF "v_$pin $pin 0 $main::BiasFor{$pin}";
                    }
                }
                print OF "x1 ".join(" ",@main::Pin)." mysub";
                if (! $main::isFloatingPin{$noisePin}) {
                    print OF "fn 0 n_$noisePin v_$noisePin 1";
                    print OF "rn 0 n_$noisePin rmod";
                }
                print OF ".ac $main::frequencySpec";
                if ($main::isFloatingPin{$noisePin}) {
                    print OF ".noise v($noisePin) vin 1";
                } else {
                    print OF ".noise v(n_$noisePin) vin 1";
                }
                print OF ".print noise onoise";
                print OF ".plot noise onoise";
            }
        }
    }
    print OF ".end";

    close(OF);

#
#   Run simulations and get the results
#

    system("$simulate::simulatorCommand $simulate::netlistFile > /dev/null");
    if (!open(SIMULATE,"<$simulate::netlistFile.chi")) {
        die("ERROR: cannot run $main::simulatorName, stopped");
    }
    $inData=0;
    $old_freq="null";
    while (<SIMULATE>) {
        chomp;s/^\s+//;s/\s+$//;@Field=split;
        if (/HERTZ\s+ONOISE/i) {$inData=1;<SIMULATE>;<SIMULATE>;next}
        if ($#Field != 1) {$inData=0;$old_freq="null";next;}
        if ($old_freq eq $Field[0]) {next;}
        next if (!$inData);
        if ($main::fMin != $main::fMax) {
            push(@X,&modelQa::unScale($Field[0]));
        }
        push(@Noise,(&modelQa::unScale($Field[1]))**2);
        $old_freq=$Field[0];
    }

    close(SIMULATE);

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

    system("cp $simulate::netlistFile $cirFile");
    system("cp $simulate::netlistFile.chi $cirFile.chi");
    if ( -f "$simulate::netlistFile.cou" )  {system("cp $simulate::netlistFile.cou $cirFile.cou")}
    #if ( -f "$simulate::netlistFile.wdb" )  {system("cp $simulate::netlistFile.wdb $cirFile.wdb")}

#
#   Clean up, unless the debug flag was specified
#

    if (! $main::debug) {
        unlink($simulate::netlistFile);
        if (defined($main::verilogaFile)) {
            $_=$main::verilogaFile;
            s/\/\S+\///;
            s/(\S+)\.va//;
            unlink("$1.ai");
            unlink("$1.info");
            unlink("$1.log");
            unlink("$1.swd");
            unlink("$1.wdb");
            unlink("$simulate::netlistFile.valog");
            system("/bin/rm -rf $simulate::netlistFile.pvadir");
        }
        if (!opendir(DIRQA,".")) {
            die("ERROR: cannot open directory ., stopped");
        }
        foreach (grep(/^$simulate::netlistFile\.ic/,readdir(DIRQA))) {unlink($_)}
        closedir(DIRQA);
    }
}

sub runAcTest {
    my($variant,$outputFile)=@_;
    my($type,$pin,$mPin,$fPin,%NextPin,$pin2);
    my(@BiasList,$i,@Field, $old_freq);
    my(@X,$omega,%g,%c,%q,$twoPi,$temperature,$biasVoltage,$sweepVoltage);
    my($inData,$inResults,$outputLine);
    my($cirFile,$resultsDirectory,$test,$circuitsDirectory);
    $circuitsDirectory="$main::resultsDirectory/circuits";
    if (! -d $circuitsDirectory) {mkdir($circuitsDirectory,0775)}
    $resultsDirectory=$main::resultsDirectory;
    $test=$main::test;
    $cirFile="$resultsDirectory/circuits/$test.$variant.cir";
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
    print OF "* AC simulation for $main::simulatorName";
    &generateCommonNetlistInfo($variant);
    @BiasList=split(/\s+/,$main::biasListSpec);
    print OF ".param vbias=$BiasList[0]";
    if (defined($main::biasSweepSpec)) {
        print OF ".param vsweep=$main::BiasSweepList[0]";
    }
    foreach $pin (@main::Pin) {
        if ($pin eq $main::Pin[0]) {
            print OF ".param ac_$pin=1";
        } else {
            print OF ".param ac_$pin=0";
        }
        if ($main::isFloatingPin{$pin}) {
            print OF "i_$pin $pin 0 0";
        } elsif ($pin eq $main::biasListPin) {
            print OF "v_$pin $pin 0 vbias ac ac_$pin";
        } elsif ($pin eq $main::biasSweepPin) {
            print OF "v_$pin $pin 0 vsweep ac ac_$pin";
        } else {
            print OF "v_$pin $pin 0 $main::BiasFor{$pin} ac ac_$pin";
        }
    }
    print OF "x1 ".join(" ",@main::Pin)." mysub";
    if ($main::fMin == $main::fMax && !defined($main::biasSweepSpec)) {
        print OF ".ac $main::frequencySpec sweep data=inputdata";
    } else {
        print OF ".ac $main::frequencySpec";
    }
    foreach $pin (@main::Pin) {
        if (!$main::isFloatingPin{$pin}) {
            print OF ".print ac ir(v_$pin) ii(v_$pin)";
            print OF ".plot ac ir(v_$pin) ii(v_$pin)";
        }
    }
    $NextPin{$main::Pin[0]}=$main::Pin[$#main::Pin];
    for ($i=1;$i<=$#main::Pin;++$i) {
        $NextPin{$main::Pin[$i]}=$main::Pin[$i-1];
    }

    if ($main::fMin == $main::fMax && !defined($main::biasSweepSpec)) {
        #   Data Sweep

        my $datasweep=".data inputdata";
        my $pinScan;
        $datasweep .= " TEMP";
        foreach $pin (@main::Pin) {
            next if (!$main::needAcStimulusFor{$pin});
            $datasweep .= " ac_${pin}";
        }
        if (defined($main::biasSweepSpec)) {
            $datasweep .= " vsweep";
        }
        $datasweep .= " vbias";
        print OF $datasweep;

        if (defined($main::biasSweepSpec)) {
            foreach $temperature (@main::Temperature) {
                foreach $biasVoltage (@BiasList) {
                    foreach $sweepVoltage (@main::BiasSweepList) {
                        foreach $pin (@main::Pin) {
                            next if (!$main::needAcStimulusFor{$pin});
                            my $sweepInput="$temperature ";
                            foreach $pinScan (@main::Pin) {
                                next if (!$main::needAcStimulusFor{$pinScan});
                                if($pin eq $pinScan){
                                    $sweepInput .= "1 ";
                                } else{
                                    $sweepInput .= "0 ";
                                }
                            }
                            $sweepInput .= "$sweepVoltage $biasVoltage";
                            print OF $sweepInput;
                        }
                    }
                }
            }
        } elsif (defined($main::tempSweepSpec)) {
            foreach $biasVoltage (@BiasList) {
                foreach $temperature (@main::TempSweepList) {
                    foreach $pin (@main::Pin) {
                        next if (!$main::needAcStimulusFor{$pin});
                        my $sweepInput="$temperature ";
                        foreach $pinScan (@main::Pin) {
                            next if (!$main::needAcStimulusFor{$pinScan});
                            if($pin eq $pinScan){
                                $sweepInput .= "1 ";
                            } else{
                                $sweepInput .= "0 ";
                            }
                        }
                        $sweepInput .= "$biasVoltage";
                        print OF $sweepInput;
                    }
                }
            }
        } else {
            die("ERROR: no sweep specification, stopped");
        }
        print OF ".enddata";

        print OF ".end";
        close(OF);

    } else {
        foreach $temperature (@main::Temperature) {
            foreach $biasVoltage (@BiasList) {
                foreach $sweepVoltage (@main::BiasSweepList) {
                    foreach $pin (@main::Pin) {
                        next if ($temperature == $main::Temperature[0] && $biasVoltage == $BiasList[0]
                                 && $sweepVoltage == $main::BiasSweepList[0] && $pin eq $main::Pin[0]);
                        print OF ".alter";
                        print OF ".temp $temperature";
                        print OF ".param vbias=$biasVoltage";
                        print OF ".param vsweep=$sweepVoltage";
                        foreach $pin2 (@main::Pin){
                            if ($pin2 ne $pin){
                                print OF ".param ac_$pin2=0";
                            } else {
                                print OF ".param ac_$pin=1";
                            }
                        }
                    }
                }
            }
        }
        print OF ".end";
        close(OF);
    }
#
#   Run simulations and get the results
#

    foreach $mPin (@main::Pin) {
        foreach $fPin (@main::Pin) {
            @{$g{$mPin,$fPin}}=();
            @{$c{$mPin,$fPin}}=();
            @{$q{$mPin,$fPin}}=();
        }
    }
    for ($i=0;$i<$#main::Pin;++$i) {
        $NextPin{$main::Pin[$i]}=$main::Pin[$i+1];
    }
    $NextPin{$main::Pin[$#main::Pin]}=$main::Pin[0];
    system("$simulate::simulatorCommand $simulate::netlistFile > /dev/null");
    if (!open(SIMULATE,"<$simulate::netlistFile.chi")) {
        die("ERROR: cannot run $main::simulatorName, stopped");
    }
    $inData=0;$inResults=0;
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
    $old_freq="null";
    while (<SIMULATE>) {
        chomp;
        if (/AC\s+ANALYSIS/i) {$inResults=1;$inData=0;next}
        if (/Job end at/)     {$inResults=0;$fPin=$NextPin{$fPin}}
        if (/ACCOUNTING INFORMATION/) {$inResults=0;$fPin=$NextPin{$fPin}}
        next if (!$inResults);
        s/^\s+//;s/\s+$//;
        if (/^HERTZ\s*\S*\(V_([a-zA-z][a-zA-Z0-9]*)\)/) {$mPin=$1;$inData=1;<SIMULATE>;<SIMULATE>;next;}
        @Field=split;
        if ($#Field != 2
            || &modelQa::unScale($Field[0]) !~ /^($main::number)$/
            || &modelQa::unScale($Field[1]) !~ /^($main::number)$/
            || &modelQa::unScale($Field[2]) !~ /^($main::number)$/) {
            $inData=0;$old_freq="null";next;
        }
        if ($old_freq eq $Field[0]) {next;}
        next if (! $inData);
        if (($main::fMin != $main::fMax) && (lc($mPin) eq lc($main::Pin[0])) && (lc($mPin) eq lc($fPin))) {
            push(@X,&modelQa::unScale($Field[0]));
        }
        $omega=$twoPi*&modelQa::unScale($Field[0]);
        push(@{$g{lc($mPin),lc($fPin)}},&modelQa::unScale($Field[1]));
        if (lc($mPin) eq lc($fPin)) {
            push(@{$c{lc($mPin),lc($fPin)}},&modelQa::unScale($Field[2])/$omega);
        } else {
            push(@{$c{lc($mPin),lc($fPin)}},-1*&modelQa::unScale($Field[2])/$omega);
        }

        if (abs(&modelQa::unScale($Field[1])) > 1.0e-99) {
            push(@{$q{lc($mPin),lc($fPin)}},&modelQa::unScale($Field[2])/&modelQa::unScale($Field[1]));
        } else {
            push(@{$q{lc($mPin),lc($fPin)}},1.0e99);
        }
        $old_freq=$Field[0];
    }
    close(SIMULATE);

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
            #printf "OUTLINE $outputLine $mPin $fPin\n";

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

    system("cp $simulate::netlistFile $cirFile");
    system("cp $simulate::netlistFile.chi $cirFile.chi");
    if ( -f "$simulate::netlistFile.cou" )  {system("cp $simulate::netlistFile.cou $cirFile.cou")}

#
#   Clean up, unless the debug flag was specified
#

    if (! $main::debug) {
        unlink($simulate::netlistFile);
        unlink("$simulate::netlistFile.st0");
        unlink("$simulate::netlistFile.chi");
        unlink("$simulate::netlistFile.id");
        if (!opendir(DIRQA,".")) {
            die("ERROR: cannot open directory ., stopped");
        }
        foreach (grep(/^$simulate::netlistFile\.ic/,readdir(DIRQA))) {unlink($_)}
        closedir(DIRQA);
        unlink("eldo.errors");
        unlink("simout.tmp");
        if (defined($main::verilogaFile)) {
            $_=$main::verilogaFile;
            s/\/\S+\///;
            s/(\S+)\.va//;
            unlink("$1.ai");
            unlink("$1.info");
            unlink("$1.log");
            unlink("$1.swd");
            unlink("$1.wdb");
            unlink("$simulate::netlistFile.valog");
            system("/bin/rm -rf $simulate::netlistFile.pvadir");
        }
    }
}

sub runDcTest {
    my($variant,$outputFile)=@_;
    my($i,$pin,@Field);
    my(@BiasList,$start,$stop,$step);
    my(@V,%DC,$temperature,$biasVoltage);
    my($inData,$inResults);
    my($conc_line);
    my($cirFile,$resultsDirectory,$test,$circuitsDirectory);
    $circuitsDirectory="$main::resultsDirectory/circuits";
    if (! -d $circuitsDirectory) {mkdir($circuitsDirectory,0775)}
    $resultsDirectory=$main::resultsDirectory;
    $test=$main::test;
    $cirFile="$resultsDirectory/circuits/$test.$variant.cir";
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
    print OF "* DC simulation for $main::simulatorName";
    &generateCommonNetlistInfo($variant);
    @BiasList=split(/\s+/,$main::biasListSpec);
    if (defined($main::biasSweepSpec)) {
        ($start,$stop,$step)=split(/\s+/,$main::biasSweepSpec);
        $start-=$step;
    } elsif (defined($main::tempSweepSpec)) {
        ($start,$stop,$step)=split(/\s+/,$main::tempSweepSpec);
        $start-=$step;
    } else {
        die("ERROR: no sweep specification, stopped");
    }
    print OF ".param vbias=$BiasList[0]";
    foreach $pin (@main::Pin) {
        if ($main::isFloatingPin{$pin}) {
            print OF "i_$pin $pin 0 0";
        } elsif ($pin eq $main::biasListPin) {
            print OF "v_$pin $pin 0 vbias";
        } elsif ($pin eq $main::biasSweepPin) {
            print OF "v_$pin $pin 0 $start";
        } else {
            print OF "v_$pin $pin 0 $main::BiasFor{$pin}";
        }
    }
    print OF "x1 ".join(" ",@main::Pin)." mysub";
    if (defined($main::biasSweepSpec)) {
        print OF ".dc v_$main::biasSweepPin $main::biasSweepSpec";
    } elsif (defined($main::tempSweepSpec)) {
        print OF ".dc temp $main::tempSweepSpec";
    }
    foreach $pin (@main::Outputs) {
        if ($pin =~ /^OP\((.*)\)/) {
            my $opname = $1;
            if (${main::keyLetter} eq 'm' && ($opname eq "gm" || $opname eq "gds")) {
                $opname .= "o";
            }
            print OF ".print x1.${main::keyLetter}1:$opname"
        } elsif ($main::isFloatingPin{$pin}) {
            print OF ".print v($pin)";
            print OF ".plot v($pin)";
        } else {
            print OF ".print i(v_$pin)";
            print OF ".plot i(v_$pin)";
        }
    }
    if (defined($main::biasSweepSpec)) {
        foreach $temperature (@main::Temperature) {
            foreach $biasVoltage (@BiasList) {
                next if ($temperature == $main::Temperature[0] && $biasVoltage == $BiasList[0]);
                print OF ".alter";
                print OF ".temp $temperature";
                print OF ".param vbias=$biasVoltage";
            }
        }
    } elsif (defined($main::tempSweepSpec)) {
        foreach $biasVoltage (@BiasList) {
            next if ($biasVoltage == $BiasList[0]);
            print OF ".alter";
            print OF ".param vbias=$biasVoltage";
        }
    }
    print OF ".end";
    close(OF);

#
#   Run simulations and get the results
#

    system("$simulate::simulatorCommand $simulate::netlistFile > /dev/null");
    if (!open(SIMULATE,"<$simulate::netlistFile.chi")) {
        die("ERROR: cannot run $main::simulatorName, stopped");
    }
    $inData=0;$inResults=0;@V=();
    foreach $pin (@main::Outputs) {
        if ($pin =~ /^OP\((.*)\)/) {
            my $opname = $1;
            if (${main::keyLetter} eq 'm' && ($opname eq "gm" || $opname eq "gds")) {
                $opname .= "o";
            }
            @{$DC{$opname}}=()
        } else {
            @{$DC{$pin}}=()
        }
    }

    while (<SIMULATE>) {
        chomp;
        if (/DC\s+TRANSFER\s+CURVES/i) {$inResults=1;$inData=0;next}
        if (/Job end at/) {$inResults=0}
        if (/ACCOUNTING INFORMATION/) {$inResults=0}
        next if (!$inResults);
        s/^\s+//;s/\s+$//;
        if (/^V\S*\s+(I|V)\([V_]*(\S*)\)/) {
            chomp($_=$2);$pin=$_;$inData=1;<SIMULATE>;<SIMULATE>;next;
        } elsif (/^volt\s+(.*)/) {
            $pin = $1;
            chomp($_=<SIMULATE>);$inData=1;next;
        } elsif (/^volt/) {
            chomp($_=<SIMULATE>);s/^\s*(x1\..1:)?//;s/\s+$//;$pin=$_;$inData=1;next;
        } elsif (/^TEMP\s+I\(V_(.*)\)/) {
            # Sample of Eldo output
            # TEMP          I(V_P)
            #X
            #
            #-4.0000000E+01  5.7142857E+00
            #-3.5000000E+01  5.0000000E+00 #
            #Y
            $pin = $1;
            chomp($_=<SIMULATE>);$inData=1;next;
        } elsif (/^Print_Legend\s+(.*):\s+VAR\(X1\.(.*)\.(.*)\)/) {
            # Sample of Eldo output
            #Print_Legend 1: VAR(X1.X1.GDIO)
            #  V_A           1
            #X
            #
            #-2.0000000E+00  4.0000000E+00
            #-1.5000000E+00  3.0000000E+00
            #Y
            $pin=$3; # $1 is legend number; $2 is keyLetter
            chomp($_=<SIMULATE>);$inData=1;next;
        }
        @Field=split;
        if ($#Field != 1
            || &modelQa::unScale($Field[0]) !~ /^($main::number)$/
            || &modelQa::unScale($Field[1]) !~ /^($main::number)$/) {
            $inData=0;
            next;
        }
        if (lc($pin) eq lc($main::Outputs[0])) {
            push(@V,&modelQa::unScale($Field[0]));
        }
        push(@{$DC{lc($pin)}},&modelQa::unScale($Field[1]));
    }
    close(SIMULATE);

#
#   Write the results to a file
#

    if (!open(OF,">$outputFile")) {
        die("ERROR: cannot open file $outputFile, stopped");
    }
    if (defined($main::biasSweepSpec)) {
        $conc_line="V($main::biasSweepPin)";
    } else {
        $conc_line="Temp";
    }
    foreach $pin (@main::Outputs) {
        if ($pin =~ /^OP/) {
            $conc_line.=" $pin";
        } elsif ($main::isFloatingPin{$pin}) {
            $conc_line.=" V($pin)";
        } else {
            $conc_line.=" I($pin)"
        }
    }
    printf OF ("$conc_line\n");
    for ($i=0;$i<=$#V;++$i) {
        next if (abs($V[$i]-$start) < abs(0.1*$step)); # this is dummy first bias point
        printf OF ("$V[$i]");
        foreach $pin (@main::Outputs) {
            if ($pin =~ /^OP\((.*)\)/) {
                my $opname = $1;
                if (${main::keyLetter} eq 'm' && ($opname eq "gm" || $opname eq "gds")) {
                    $opname .= "o";
                }
                printf OF (" ${$DC{$opname}}[$i]")
            } else {
                printf OF (" ${$DC{$pin}}[$i]")
            }
        }
        printf OF ("\n");
    }
    close(OF);

    system("cp $simulate::netlistFile $cirFile");
    system("cp $simulate::netlistFile.chi $cirFile.chi");
    if ( -f "$simulate::netlistFile.cou" )  {system("cp $simulate::netlistFile.cou $cirFile.cou")}
#    if ( -f "$simulate::netlistFile.wdb" )  {system("cp $simulate::netlistFile.wdb $cirFile.wdb")}

#
#   Clean up, unless the debug flag was specified
#
    if (! $main::debug) {
        unlink($simulate::netlistFile);
        unlink("$simulate::netlistFile.st0");
        unlink("$simulate::netlistFile.chi");
#        unlink("$simulate::netlistFile.wdb");
        unlink("$simulate::netlistFile.id");
        if (!opendir(DIRQA,".")) {
            die("ERROR: cannot open directory ., stopped");
        }
        foreach (grep(/^$simulate::netlistFile\.ic/,readdir(DIRQA))) {unlink($_)}
        closedir(DIRQA);
        unlink("eldo.errors");
        unlink("simout.tmp");
        if (defined($main::verilogaFile)) {
            $_=$main::verilogaFile;
            s/\/\S+\///;
            s/(\S+)\.va//;
            unlink("$1.ai");
            unlink("$1.info");
            unlink("$1.log");
            unlink("$1.swd");
            unlink("$1.wdb");
            unlink("$simulate::netlistFile.valog");
            system("/bin/rm -rf $simulate::netlistFile.pvadir");
        }
    }
}

sub generateCommonNetlistInfo {
    my($variant)=$_[0];
    my(@Pin_x,$arg,$name,$value,$eFactor,$fFactor,$pin,$vlaName,@SelectionArgs);
    if (!defined($main::keyLetter)) {
        if (defined($main::verilogaFile)) {
            $main::keyLetter="x";
        } else {
            die("ERROR: no keyLetter specified, stopped");
        }
    }
    print OF ".option numdgt=7";
#    print OF ".option TMAX=400 TMIN=-400"; Uncomment when needed
    print OF ".option tnom=27";
    if ($main::globalScaleFactor ne 1) {
        print OF ".option scale=$main::globalScaleFactor";
    }
    if ($main::omiOption ne "") {
        print OF ".option $main::omiOption";
    }
    print OF ".temp $main::Temperature[0]";
    if ($variant=~/^scale$/) {
        print OF ".option scale=$main::scaleFactor";
    }
    if ($variant=~/^shrink$/) {
        print OF ".option scale=".(1.0-$main::shrinkPercent*0.01);
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
        if (defined($main::verilogaFile)) {
            print OF ".option ymfact";
        }
    }
    if (defined($main::verilogaFile)) {
        print OF ".hdl '$main::verilogaFile'";
    }
    foreach $pin (@main::Pin) {push(@Pin_x,"${pin}_x")}
    print OF ".subckt mysub ".join(" ",@Pin_x);
    foreach $pin (@main::Pin) {
        if ($main::isFloatingPin{$pin}) { # assumed "dt" thermal pin, no scaling sign change
            print OF "v_$pin ${pin} ${pin}_x 0";
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
    if (defined($main::verilogaFile)) {
        if ($variant=~/_P/) {
            ($vlaName,@SelectionArgs)=split(/\s+/,$main::pTypeSelectionArguments);
        } else {
            ($vlaName,@SelectionArgs)=split(/\s+/,$main::nTypeSelectionArguments);
        }
#        if ((($#SelectionArgs>=0) && ($SelectionArgs[0]!~/^(generic:|param:)$/i)) || (@main::ModelParameters) ) {
#            splice(@SelectionArgs,0,0,"generic:");
#        }
        print OF "X1 ".join(" ",@main::Pin,$vlaName,@SelectionArgs);
        if ($variant=~/^scale$/) {
            print OF "+ scale=$main::scaleFactor";
        }
        if ($variant=~/^shrink$/) {
            print OF "+ shrink=$main::shrinkPercent";
        }
    } else {
        print OF "${main::keyLetter}1 ".join(" ",@main::Pin)." MYMODEL";
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
    if (! defined($main::verilogaFile)) {
        if ($variant=~/_P/) {
            print OF ".model MYMODEL $main::pTypeSelectionArguments";
        } else {
            print OF ".model MYMODEL $main::nTypeSelectionArguments";
       }
    }
    foreach $arg (@main::ModelParameters) {
        print OF "+ $arg";
    }
    print OF ".ends";
}

1;
