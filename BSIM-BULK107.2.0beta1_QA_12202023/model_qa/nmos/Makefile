
# Copyright (C) 2023 Silicon Integration Initiative, Inc., All rights reserved.
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

#  Rel   Date            Who                Comments                                                                                  
#  ====  ==========      ===============      ========                                                                                  
#  3.3.4  06/06/23	 Shahriar Moinian     Removed referneces to nexxim simulator
#   	  		 	  	      Changed copyright sympol
#					      Added the VA cache directory to clean target for SmartSpice
#  2.3.0  12/09/19       Shahriar Moinian     Modified simulator target wildcard to support gnu make 3.82 or later
#
#	Example Makefile to run tests and check results.
#
#	This is an example makefile for running QA tests on a
#	model and then checking the simulated results against
#	reference results. A separate target is defined for each
#	variant of the model. The program runQaTests.pl runs the
#	tests, and that program expects a perl module SIMULATOR.pm
#	to be provided for each simulator that is tested.
#	Examples of these are provided.
#

qaSpecFile		=	qaSpec
qaResultsDirectory	=	results
testProgramName		=	../../lib/runQaTests.pl
#testProgramName		=	runQaTests.pl
testProgramFlags        =       -nw
#testProgramFlags        =       -d

help:
	@echo "" ; \
	echo "Valid targets are:" ; \
	echo "" ; \
	echo "all                run tests and compare results for all simulators" ; \
	echo "" ; \
	echo "spice              run tests and compare results spice" ; \
	echo "hspice             run tests and compare results hspice" ; \
	echo "spectre            run tests and compare results spectre" ; \
	echo "ads                run tests and compare results ads" ; \
	echo "eldo               run tests and compare results eldo" ; \
	echo "smartspice         run tests and compare results smartspice" ; \
	echo "" ; \
	echo "clean              remove all previously generated simulation results"; \
	echo "" ; \
	echo "NOTE: if test results exist they are not resimulated" ; \
	echo "NOTE: to force resimulation run \"make clean\" first" ; \
	echo ""

all:	spice hspice spectre ads eldo smartspice

#####
##### common target for all simulators
#####

%:
	@-echo ""; \
	localPlatform=`$(testProgramName) -platform` ; \
	localVersion=`$(testProgramName) -sv -s $@ $(qaSpecFile) | awk '{print $$1}'` ; \
	localVersionAndPlatform=$$localVersion._.$$localPlatform ; \
	localResultsDir="results/$@/$$localVersion/$$localPlatform"; \
	echo "******"; \
	echo "****** $(qaSpecFile) tests for $@"; \
	echo "****** (for version $$localVersion on platform $$localPlatform)"; \
	echo "******"; \
	for test in `$(testProgramName) -lt -s $@ $(qaSpecFile)` ; \
	do \
	    echo ""; \
	    echo "****** Checking test ($@): $$test" ; \
	    for variant in `$(testProgramName) -lv -s $@ $(qaSpecFile)` ; \
	    do \
	        $(testProgramName) $(testProgramFlags) -s $@ -o $$localResultsDir -t $$test -var $$variant $(qaSpecFile) ; \
	    done ; \
	done ; \
	for version in `ls -C1 $(qaResultsDirectory)/$@` ; \
	do \
	    for platform in `ls -C1 $(qaResultsDirectory)/$@/$$version` ; \
	    do \
	        versionAndPlatform=$$version._.$$platform ; \
	        if [ $$versionAndPlatform = $$localVersionAndPlatform ] ; \
	        then \
	            break ; \
	        fi ; \
	        echo "" ; \
	        echo "******"; \
	        echo "****** Comparing previously run $(qaSpecFile) tests for $@"; \
	        echo "****** (for version $$version on platform $$platform)"; \
	        echo "******"; \
	        for test in `$(testProgramName) -lt -s $@ $(qaSpecFile)` ; \
	        do \
	            echo ""; \
	            echo "****** Checking test ($@): $$test" ; \
	            for variant in `$(testProgramName) -lv -s $@ $(qaSpecFile)` ; \
	            do \
	                $(testProgramName) -c $$version $$platform -s $@ -t $$test -var $$variant $(qaSpecFile) ; \
	            done ; \
	        done ; \
	    done ; \
	done

clean:
	@/bin/rm -rf $(qaResultsDirectory)/spice spiceCkt*
	@/bin/rm -rf $(qaResultsDirectory)/hspice hspiceCkt*
	@/bin/rm -rf $(qaResultsDirectory)/spectre spectreCkt* *ahdlcmi
	@/bin/rm -rf $(qaResultsDirectory)/ads adsCkt* .adsCkt.* spectra.raw SimLog
	@/bin/rm -rf $(qaResultsDirectory)/eldo eldoCkt*
	@/bin/rm -rf $(qaResultsDirectory)/smartspice smartspiceCkt* SilvacoVLG

