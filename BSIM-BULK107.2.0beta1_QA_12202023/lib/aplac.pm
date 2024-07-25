
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
#   Aplac DC, AC and noise test routines
#
#
#  Rel  Date            Who              Comments
# ====  ==========      =============    ========
#  3.3  08/31/2022	Shahriar Moinian Added initial results file cleanup
#  2.1  10/03/17        Shahriar Moinian Added SI2 clauses
#  0.91 09/21/2017      Juha Volotinen   Fixed dec frequency sweep and DC biassweep with negative step,
#                                        No OP support, no VA support, no version extraction
#  0.9  09/05/2017      Juha Volotinen   No OP support, no VA support, no version extraction
#                                       

package simulate;
if (defined($main::simulatorCommand)) {
    $simulatorCommand=$main::simulatorCommand;
} else {
    $simulatorCommand="\$APLAC_BIN -ntw -aq ";
}
$netlistFile="aplacCkt";
$dummyVaFile="cmcQaDummy.va";
$vaVersion="unknown";
$vaUseModelCard=0;
use strict;

sub version {
    my($version);
    $version="unknown";
       
    # add version extraction code
    return("9.5","none");
}

sub runNoiseTest {
    my($variant,$outputFile)=@_;
    my($arg,$name,$value,$i,$j,$k,$type,$pin,$noisePin);
    my(@BiasList,@Field,$inData);
    my($temperature,$biasVoltage);
    my(@X,@Noise);
    my $aplacResDir="aplacCkt.raw";
    my $mSteps;

    use POSIX;
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
    print OF "\$ // Noise simulation for $main::simulatorName\n";
    print OF "Prepare NOISE RMAX=1.0e14 FORMAT=\"%18.10E\"  \n";
    &generateCommonNetlistInfo($variant);
    @BiasList=split(/\s+/,$main::biasListSpec);
    foreach $pin (@main::Pin) {
        if ($main::isFloatingPin{$pin}) {
            print OF "CURR i_$pin ($pin 0)  DC=0";
            #print OF "save $pin";
        } else {
            if (defined($main::referencePinFor{$pin})) {
		print OF "VAR v_$pin = $main::BiasFor{$pin}";
                print OF "VAR vf_$pin = FUNC v_$pin";
                print OF "VOLT v_$pin $pin ${pin}_$main::referencePinFor{$pin} DC=vf_$pin";
                print OF "VCVS e_${pin} ${pin}_$main::referencePinFor{$pin} 0  1 $main::referencePinFor{$pin} 0 1 I=b_$pin";
            } else {
		print OF "VAR v_$pin = $main::BiasFor{$pin}";
                print OF "VAR vf_$pin = FUNC v_$pin";
                print OF "VOLT v_$pin $pin 0 DC=vf_$pin I=b_$pin";
            }
            #print OF "save v_$pin:p";
        }
    }
    print OF "mysub x1 ".join(" ",@main::Pin)." ";
    $aplacResDir="$simulate::netlistFile.raw";
    $noisePin=$main::Outputs[0];
    if ($main::outputNoise == 2) {
        $noisePin="($noisePin,$main::Outputs[1])";
    } elsif (! $main::isFloatingPin{$noisePin}) {
        print OF "CCCS fn 0 n_$noisePin 1 b_$noisePin 1";
        print OF "RES rn 0 n_$noisePin 1 NOISELESS";
        $noisePin="n_$noisePin";
    }
    for ($j=0;$j<=$#main::Temperature;++$j) {
        print OF "SetParam TEMPC=$main::Temperature[$j]";
        #print OF "alterT$j alter param=temp value=$main::Temperature[$j]";
        for ($i=0;$i<=$#BiasList;++$i) {
            if ($main::biasListPin ne "dummyPinNameThatIsNeverUsed") {
                print OF "Call v_$main::biasListPin = $BiasList[$i]";
                #print OF "alterT${j}_$i alter dev=v_$main::biasListPin param=dc value=$BiasList[$i]";
            }
            for ($k=0;$k<=$#main::BiasSweepList;++$k) {
                if (!$main::isFloatingPin{$main::biasSweepPin} && $main::biasSweepPin ne "dummyPinNameThatIsNeverUsed") {
		    print OF "Call v_$main::biasSweepPin = $main::BiasSweepList[$k]";
                    #print OF "alterT${j}_${i}_$k alter dev=v_$main::biasSweepPin param=dc value=$main::BiasSweepList[$k]";
                }
		if (! -d $aplacResDir) {mkdir($aplacResDir,0775)};
	        print OF ("Print OPENFILE \"$simulate::netlistFile.raw/noise_t${j}_bl${i}_bs${k}.noise\"");
 		print OF ("+ S \"VALUE\" LF");
                print OF (" ");
                print OF "Analyze DC";
                if ($main::fMin == $main::fMax) {
			print OF "Analyze AC FREQ=$main::fMin ";
 		    	print OF ("Print APPENDFILE \"$simulate::netlistFile.raw/noise_t${j}_bl${i}_bs${k}.noise\"");
 		    	print OF ("+ ASCII 34 S \"freq\" ASCII 34 S \" $main::fMin \" LF");
                        print OF ("+ ASCII 34 S \"out\" ASCII 34 S \" \" REAL VacNoise($noisePin,0) LF");
                    #print OF "noise_t${j}_bl${i}_bs${k} $noisePin noise values=[$main::fMin]";
                } else {
			print OF "Sweep \" noise_t${j}_bl${i}_bs${k}\"";
                        if ($main::fType eq "dec") {
                         $mSteps= 1+(floor(0.5+(log($main::fMax)-log($main::fMin))/log(10)))*($main::fSteps);
                         print OF "+ LOOP $mSteps FREQ LOG $main::fMin $main::fMax";
                        } else {
                         print OF "+ LOOP 1+$main::fSteps FREQ $main::fType $main::fMin $main::fMax";
                        }
                        print OF " ";
 		    	print OF ("Print APPENDFILE \"$simulate::netlistFile.raw/noise_t${j}_bl${i}_bs${k}.noise\"");
 		    	print OF ("+ ASCII 34 S \"freq\" ASCII 34 S \" \" REAL f LF");
                        print OF ("+ ASCII 34 S \"out\" ASCII 34 S \" \" REAL VacNoise($noisePin,0) LF");
                        #print OF "noise_t${j}_bl${i}_bs${k} $noisePin noise start=$main::fMin stop=$main::fMax $main::fType=$main::fSteps";
                        print OF "EndSweep";
                }
                print OF ("Print APPENDFILE \"$simulate::netlistFile.raw/noise_t${j}_bl${i}_bs${k}.noise\" S \"END\"");
            }
        }
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
        foreach $temperature (@main::Temperature) {
            foreach $biasVoltage (split(/\s+/,$main::biasListSpec)) {
                push(@X,@main::BiasSweepList);
            }
        }
    }
    for ($j=0;$j<=$#main::Temperature;++$j) {
        for ($i=0;$i<=$#BiasList;++$i) {
            for ($k=0;$k<=$#main::BiasSweepList;++$k) {
                $inData=0;
                if (! open(IF,"$simulate::netlistFile.raw/noise_t${j}_bl${i}_bs${k}.noise")) {
                    die("ERROR: cannot open file noise_t${j}_bl${i}_bs${k}.noise, stopped");
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
        printf OF ("V($main::biasSweepPin)");
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
        if (defined($main::verilogaFile)) {
            system("/bin/rm -rf $main::verilogaFile.*.ahdlcmi $simulate::netlistFile.ahdlSimDB");
        }
        system("/bin/rm -rf $simulate::netlistFile.raw $simulate::netlistFile.log");
    }
}

sub runAcTest {
    my($variant,$outputFile)=@_;
    my($arg,$name,$value,$i,$j,$k,$type,$pin,$mPin,$fPin,$first_fPin);
    my(@BiasList,@Field,$inData);
    my($temperature,$biasVoltage);
    my(@X,$omega,%g,%c,%q,$twoPi,$outputLine);
    $twoPi=8.0*atan2(1.0,1.0);
    my $aplacResDir="aplacCkt.raw";
    my $sPin;
    my $mSteps;

    use POSIX;
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
    print OF "\$ // AC simulation for $main::simulatorName\n";
    print OF "Prepare RMAX=1.0e14  FORMAT=\"%18.6E\"  \n";
    &generateCommonNetlistInfo($variant);
    @BiasList=split(/\s+/,$main::biasListSpec);
    foreach $pin (@main::Pin) {
        if ($main::isFloatingPin{$pin}) {
            print OF "CURR i_$pin $pin 0 DC=0";
            #print OF "save $pin";
        } else {
            if (defined($main::referencePinFor{$pin})) {
                print OF "VAR v_$pin = $main::BiasFor{$pin}";
                print OF "VAR vf_$pin = FUNC v_$pin";
                print OF "VOLT v_$pin $pin ${pin}_$main::referencePinFor{$pin} DC=vf_$pin";
                print OF "VCVS e_${pin} ${pin}_$main::referencePinFor{$pin} 0  1 $main::referencePinFor{$pin} 0 1 I=b_$pin";
            } else {
                print OF "VAR v_$pin = $main::BiasFor{$pin}";
                print OF "VAR vf_$pin = FUNC v_$pin";
                print OF "VAR vac_$pin = 0";
                print OF "VAR vfac_$pin = FUNC vac_$pin";
                print OF "VOLT v_$pin $pin 0 DC=vf_$pin AC=vfac_$pin I=b_$pin";
            }
            #print OF "save v_$pin:p";
            print OF " ";
        }
    }
    print OF "mysub x1 ".join(" ",@main::Pin)." ";
 
    $aplacResDir="$simulate::netlistFile.raw";

    for ($j=0;$j<=$#main::Temperature;++$j) {
        print OF "SetParam TEMPC=$main::Temperature[$j]";
        #print OF "alterT$j alter param=temp value=$main::Temperature[$j]";
        for ($i=0;$i<=$#BiasList;++$i) {
            if ($main::biasListPin ne "dummyPinNameThatIsNeverUsed") {
                #print OF "alterT${j}_$i alter dev=v_$main::biasListPin param=dc value=$BiasList[$i]";
                print OF "Call v_$main::biasListPin = $BiasList[$i]";
            }
            for ($k=0;$k<=$#main::BiasSweepList;++$k) {
                if ($main::biasSweepPin ne "dummyPinNameThatIsNeverUsed") {
	            print OF "Call v_$main::biasSweepPin = $main::BiasSweepList[$k]";
                    #print OF "alterT${j}_${i}_$k alter dev=v_$main::biasSweepPin param=dc value=$main::BiasSweepList[$k]";
                }
                foreach $pin (@main::Pin) {
                    next if (!$main::needAcStimulusFor{$pin});
		    if (! -d $aplacResDir) {mkdir($aplacResDir,0775)};
	            print OF "Call vac_$pin=1";
 		    print OF ("Print OPENFILE \"$simulate::netlistFile.raw/acT${j}_${i}_${k}_$pin.ac\"");
 		    print OF ("+ S \"VALUE\" LF");
                    print OF (" ");
                    #print OF "setT${j}_${i}_${k}_$pin alter dev=v_$pin param=mag value=1";
                    print OF "Analyze DC";
                    if ($main::fMin == $main::fMax) {
                       # print OF "acT${j}_${i}_${k}_$pin ac values=[$main::fMin]";
                        print OF "Analyze AC FREQ=$main::fMin ";
 		    	print OF ("Print APPENDFILE \"$simulate::netlistFile.raw/acT${j}_${i}_${k}_$pin.ac\"");
 		    	print OF ("+ ASCII 34 S \"freq\" ASCII 34 S \" $main::fMin \" LF");
                        foreach $sPin (@main::Pin) {
				print OF "+ ASCII 34 S \"v_$sPin\:p\" ASCII 34  S \" (\" REAL Re(Iac(b_$sPin)) S \" \" REAL Im(Iac(b_$sPin)) S \")\"  LF ";
                        } 
                    } else {
                        print OF "Sweep \" setT${j}_${i}_${k}_$pin\"";
                        if ($main::fType eq "dec") {
                         $mSteps= 1+(floor(0.5+($main::fSteps)*(log($main::fMax)-log($main::fMin))/log(10)));
                         print OF "+ LOOP $mSteps FREQ LOG $main::fMin $main::fMax";
                        } else {
                         print OF "+ LOOP 1+$main::fSteps FREQ $main::fType $main::fMin $main::fMax";
                        }
                        print OF " ";
 		    	print OF ("Print APPENDFILE \"$simulate::netlistFile.raw/acT${j}_${i}_${k}_$pin.ac\"");
 		    	print OF ("+ ASCII 34 S \"freq\" ASCII 34 S \" \" REAL f LF");
                        foreach $sPin (@main::Pin) {
				print OF "+ ASCII 34 S \"v_$sPin\:p\" ASCII 34  S \" (\" REAL Re(Iac(b_$sPin)) S \" \" REAL Im(Iac(b_$sPin)) S \")\"  LF ";
                        }
                        #print OF "acT${j}_${i}_${k}_$pin ac start=$main::fMin stop=$main::fMax $main::fType=$main::fSteps";
                       print OF "EndSweep";
                    }
                    #print OF "unsetT${j}_${i}_${k}_$pin alter dev=v_$pin param=mag value=0";
                    print OF "Call vac_$pin=0";
                    print OF ("Print APPENDFILE \"$simulate::netlistFile.raw/acT${j}_${i}_${k}_$pin.ac\" S \"END\"");
                }

            }
        }
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
        foreach $temperature (@main::Temperature) {
            foreach $biasVoltage (split(/\s+/,$main::biasListSpec)) {
                push(@X,@main::BiasSweepList);
            }
        }
    }
    $fPin=$main::Pin[0];
    for ($j=0;$j<=$#main::Temperature;++$j) {
        for ($i=0;$i<=$#BiasList;++$i) {
            for ($k=0;$k<=$#main::BiasSweepList;++$k) {
                foreach $fPin (@main::Pin) {
                    next if (!$main::needAcStimulusFor{$fPin});
                    $inData=0;
                    if (! open(IF,"$simulate::netlistFile.raw/acT${j}_${i}_${k}_$fPin.ac")) {
                        die("ERROR: cannot open file $simulate::netlistFile.raw/acT${j}_${i}_${k}_$fPin.ac, stopped");
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
        printf OF ("V($main::biasSweepPin)");
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
        if (defined($main::verilogaFile)) {
            system("/bin/rm -rf $main::verilogaFile.*.ahdlcmi $simulate::netlistFile.ahdlSimDB");
        }
        system("/bin/rm -rf $simulate::netlistFile.raw $simulate::netlistFile.log");
    }
}

sub runDcTest {
    my($variant,$outputFile)=@_;
    my($arg,$name,$value,$i,$j,$pin,@Field,$inData);
    my(@BiasList,$start,$stop,$step);
    my(@V,%DC);
    my $aplacResDir="aplacCkt.raw";
    my $mSteps;
    my $vJ;
    my $swStop;
    my $continueSteps;
    my @biasVector;
    my $mVecInd;
  
    use POSIX ;
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
#   One extra point is added at the beginning of the sweep as in the Spectre tests.
#

    system("/bin/rm -rf $outputFile");
    if (!open(OF,">$simulate::netlistFile")) {
        die("ERROR: cannot open file $simulate::netlistFile, stopped");
    }
    print OF "\$ // DC simulation for $main::simulatorName\n";
    print OF "Prepare RMAX=1.0e14  FORMAT=\"%18.6E\"  \n";
    &generateCommonNetlistInfo($variant);
    @BiasList=split(/\s+/,$main::biasListSpec);
    ($start,$stop,$step)=split(/\s+/,$main::biasSweepSpec);
    $start-=$step;
    foreach $pin (@main::Pin) {
        if ($main::isFloatingPin{$pin}) {
            print OF "CURR i_$pin $pin 0 DC=0";
            #print OF "save $pin";
        } else {
            if (defined($main::referencePinFor{$pin})) {
                print OF "VAR v_$pin = $main::BiasFor{$pin}";
                print OF "VAR vf_$pin = FUNC v_$pin";
                print OF "VOLT v_$pin $pin ${pin}_$main::referencePinFor{$pin} DC=vf_$pin";
                print OF "VCVS e_${pin} ${pin}_$main::referencePinFor{$pin} 0  1 $main::referencePinFor{$pin} 0 1 I=b_$pin";
            } else {
                print OF "VAR v_$pin = $main::BiasFor{$pin}";
                print OF "VAR vf_$pin = FUNC v_$pin";
                print OF "VOLT v_$pin $pin 0 DC=vf_$pin I=b_$pin";
            }
#            print OF "save v_$pin:p";
             print OF " ";
          }
    }
#    if ($main::outputOp) {
#        foreach $pin (@main::Outputs) {
#            if ($pin =~ /^OP\((.*)\)/) {
#                print OF "save x1.${main::keyLetter}1:$1";
#            }
#        }
#    }
    print OF "mysub x1 ".join(" ",@main::Pin)." ";

    $aplacResDir="$simulate::netlistFile.raw";
    if (! -d $aplacResDir) {mkdir($aplacResDir,0775)};

    for ($j=0;$j<=$#main::Temperature;++$j) {
        print OF "SetParam TEMPC=$main::Temperature[$j]";
        for ($i=0;$i<=$#BiasList;++$i) {
            if ($main::biasListPin ne "dummyPinNameThatIsNeverUsed") {
                print OF "Call v_$main::biasListPin = $BiasList[$i]";
            }
 	    print OF ("Print OPENFILE \"$simulate::netlistFile.raw/dcT${j}_$i.dc\"");
            print OF ("+ S \"VALUE\" LF");
            print OF (" ");
            $mSteps=0;
            $continueSteps=1;

            print OF ("Declare VECTOR sweepVector_${i}_$j  REAL ");
            if ($stop >= $start ) {
            for ($vJ=$start;$continueSteps;$vJ=$vJ+$step) {
                if ($vJ>=$stop) {
                  $swStop = $stop;
                  $continueSteps=0;
                  if (($vJ-$stop)>0.9999*$step) {
                    $biasVector[-1]=$swStop;
                  } else {
                    ++$mSteps;
                    push(@biasVector,$swStop);
                   }
                 
                } else { 
                  ++$mSteps;                   
     	          $swStop=$vJ;
                  push(@biasVector,$vJ);
                }
#            print "msteps $mSteps continue $continueSteps vj $vJ  stop $swStop";
            }
	    } else {
            for ($vJ=$start;$continueSteps;$vJ=$vJ+$step) {
                if ($vJ<=$stop) {
                  $swStop = $stop;
                  $continueSteps=0;
                  if (abs($vJ-$stop)>0.9999*abs($step)) {
                    $biasVector[-1]=$swStop;
                  } else {
                    ++$mSteps;
                    push(@biasVector,$swStop);                    
                   }
                 
                } else { 
                  ++$mSteps;                   
     	          $swStop=$vJ;
                  push(@biasVector,$vJ);
                }
            }
            }
            $mVecInd=$mSteps-1;
            print OF "+ $mVecInd ";
            #$mVecInd=$#main::BiasSweepList;
            #print OF "+ $mVecInd ";

            print OF (" ");
            print OF "Init sweepVector_${i}_$j ";
            foreach $vJ (@biasVector) {
              print OF "+ $vJ"; 
            }
            print OF (" ");

            @biasVector = ();

	    #foreach $vJ (@main::BiasSweepList) {
            #  print OF "+ $vJ";
            #}
            #print OF (" ");

            print OF "Sweep \"dcT${j}_$i\" "; 
            print OF "+ dc"; 
            #$mSteps= 1+floor(0.5+($stop-$step-$start)/$step);
            print OF "+ LOOP $mVecInd+1 VAR v_$main::biasSweepPin TABLE sweepVector_${i}_$j";
            print OF (" ");
            print OF "Print APPENDFILE \"$simulate::netlistFile.raw/dcT${j}_$i.dc\"";
	    print OF ("+ ASCII 34 S \"dc\" ASCII 34 S \" \" REAL v_$main::biasSweepPin S \" \" LF");
	    foreach $pin (@main::Outputs) {
                if ($pin =~ /^OP/) {
            		print OF ("+ S \" $pin\"");
        	} elsif ($main::isFloatingPin{$pin}) {
	            print OF ("+ ASCII 34 S \"v_$pin\:p\" ASCII 34  S \" \" REAL Vdc($pin) S \" \" LF");
	        } else {
        	    print OF ("+ ASCII 34 S \"v_$pin\:p\" ASCII 34  S \" \" REAL  Idc(b_$pin) S \" \" LF");
        	}
    	    }
           print OF ("EndSweep");
           print OF ("Print APPENDFILE \"$simulate::netlistFile.raw/dcT${j}_$i.dc\" S \"END\"");
        }
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
    for ($j=0;$j<=$#main::Temperature;++$j) {
        for ($i=0;$i<=$#BiasList;++$i) {
            $inData=0;
            if (! open(IF,"$simulate::netlistFile.raw/dcT${j}_$i.dc")) {
                die("ERROR: cannot open file $simulate::netlistFile.raw/dcT${j}_$i.dc, stopped");
            }
            while (<IF>) {
                chomp;
                if (/VALUE/) {$inData=1}
                next if (! $inData);
                s/"//g;s/:p//;s/^\s+//;s/\s+$//;
                next if (/:p/);
                @Field=split;
                if ($Field[0] eq "dc") {push(@V,$Field[1]);next}
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
    printf OF ("V($main::biasSweepPin)");
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
        if (defined($main::verilogaFile)) {
            system("/bin/rm -rf $main::verilogaFile.*.ahdlcmi $simulate::netlistFile.ahdlSimDB");
        }
        system("/bin/rm -rf $simulate::netlistFile.raw $simulate::netlistFile.log");
    }
}

sub generateCommonNetlistInfo {
    my($variant)=$_[0];
    my(@Pin_x,$arg,$name,$value,$eFactor,$fFactor,$pin);
    print OF "\$ APLAC test simulation file\n";
    print OF "\#ifdef __LINUX64 \n";
    print OF "\#LOAD \"aplac_cmc_models.so\" TYPE=MODEL INITFUNCTION=init_model_c ";
    print OF "\#endif \n";

    if ($simulate::vaVersion eq "LRM2.2") {
        if ($variant=~/^scale$/) {
            print OF "\$ testOptions options scale=$main::scaleFactor";
        }
        if ($variant=~/^shrink$/) {
            print OF "\$ testOptions options scale=".(1.0-$main::shrinkPercent*0.01);
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
        print OF "\$ ahdl_include \"$main::verilogaFile\"";
    }
    foreach $pin (@main::Pin) {push(@Pin_x,"${pin}_x")}
    print OF "DefModel mysub " .scalar @Pin_x .  " " .join(" ",@Pin_x)." ";
    foreach $pin (@main::Pin) {
        if ($main::isFloatingPin{$pin}) {
            if ($main::outputNoise && $pin eq $main::Outputs[0]) {
                if ($variant=~/^m$/) {
                    $eFactor=sqrt($main::mFactor);
                } else {
                    $eFactor=1;
                }
                print OF "VCVS e_$pin ${pin}_x 1 ${pin} 0 $eFactor";
            } else { # assumed "dt" thermal pin, no scaling sign change
                print OF "VOLT v_$pin (${pin} ${pin}_x) DC=0";
            }
        } elsif ($variant=~/^Flip/ && defined($main::flipPin{$pin})) {
            print OF "VCVS e_$pin ${pin}   0  1 $main::flipPin{$pin}_x 0 $eFactor I=e_$pin";
            print OF "CCCS f_$pin $main::flipPin{$pin}_x 0 1 e_$pin $fFactor";
        } else {
            print OF "VCVS e_$pin ${pin}   0 1 ${pin}_x 0 $eFactor I=e_$pin";
            print OF "CCCS f_$pin ${pin}_x 0 1 e_$pin $fFactor";
        }
    }
    if (!defined($main::verilogaFile) || $simulate::vaUseModelCard) {
        if ($variant=~/_P/) {
	        my @aplacModelName = split(/ /,$main::pTypeSelectionArguments);
        	my $i;
        	print OF "$aplacModelName[0] ${main::keyLetter}1 ".join(" ",@main::Pin)." ";
        	for ($i=1;$i<=$#aplacModelName;++$i) {
                	print OF "+ $aplacModelName[$i]";
        	}
        	print OF "+ IGNOREBUILTINETPARAMS";
        } else {
	        my @aplacModelName = split(/ /,$main::nTypeSelectionArguments);
        	my $i;
        	print OF "$aplacModelName[0] ${main::keyLetter}1 ".join(" ",@main::Pin)." ";
        	for ($i=1;$i<=$#aplacModelName;++$i) {
                	print OF "+ $aplacModelName[$i]";
        	}
        	print OF "+ IGNOREBUILTINETPARAMS";
        }
    } else {
        if ($variant=~/_P/) {
	    my @aplacModelName = split(/ /,$main::pTypeSelectionArguments);
            my $i;
            print OF "$aplacModelName[0] ${main::keyLetter}1 ".join(" ",@main::Pin) ;
            for ($i=1;$i<=$#aplacModelName;++$i) {
                print OF "+ $aplacModelName[$i]";
            }
            print OF "+ IGNOREBUILTINETPARAMS";
        } else {
	    my @aplacModelName = split(/ /,$main::nTypeSelectionArguments);
            my $i;
            print OF "$aplacModelName[0] ${main::keyLetter}1 ".join(" ",@main::Pin) ;
#            print OF "Bsim3 ${main::keyLetter}1 ".join(" ",@main::Pin). " w = 1u l = 1u" ;
            for ($i=1;$i<=$#aplacModelName;++$i) {
                print OF "+ $aplacModelName[$i]";
            }
            print OF "+ IGNOREBUILTINETPARAMS";
        }
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
        print OF "+ multiplier=$main::mFactor";
    }
#    if (!defined($main::verilogaFile) || $simulate::vaUseModelCard) {
#        if ($variant=~/_P/) {
#            my @aplacModelName = split(/ /,$main::pTypeSelectionArguments);
#            my $i;
#            print OF "model mymodel ";
#            for ($i=1;$i<=$#aplacModelName;++$i) {
#                print OF "+ $aplacModelName[$i]";
#            }
#            print OF "+ IGNOREBUILTINETPARAMS";
#        } else {
#            my @aplacModelName = split(/ /,$main::pTypeSelectionArguments);
#            my $i;
#            print OF "model mymodel ";
#            for ($i=1;$i<=$#aplacModelName;++$i) {
#                print OF "+ $aplacModelName[$i]";
#            }
#            print OF "+ IGNOREBUILTINETPARAMS";
#        }
#    }
    foreach $arg (@main::ModelParameters) {
        ($name,$value)=split(/=/,$arg);
        if (($name eq "TNOM") or ($name eq "tnom")) {
		print OF "+ TNOM_=$value";
        } else {
        	if ($name eq "GMIN") {
			print OF "\$+ GMIN=$value";
        	} else {
        	if ($name eq "KUOXXY") {
			print OF "\$+ $arg";
                } else {

        	if ($name eq "KVTHOXXY") {
			print OF "\$+ $arg";
                } else {
		        print OF "+ $arg";
        	}
               }
             }
        }
    }
    print OF "EndModel";
}

1;
