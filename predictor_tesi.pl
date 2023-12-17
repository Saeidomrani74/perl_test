#!/bin/perl 

############################################# INCLUSIONI ################################
 use Data::Dumper qw(Dumper);
 use threads; #modulo che implementa il multi-threading / utilizzare il modulo threads se si opera sotto windows
 use Algorithm::Combinatorics qw(variations_with_repetition);
 use Path::Tiny qw(path); #file manipulation
 use File::Find::Rule;
 use DBI;
 use Switch;
 use POSIX;
 use Time::HiRes qw (sleep);
 use DateTime;
 use Math::Gauss ':all';
 use Statistics::LineFit;
 use List::Util qw(max);
 use List::Util qw(sum);
 #use lib 'C:\Users\Michele Scaratti\Desktop\MICHELE\universita\specialistica_ing-inf\tesi\progetto';#libreria personale
 #use lib '/home/mich/Scrivania/varie/uni/tesi/progetto';#libreria personale
 use classes_predictor_tesi; #modulo del progetto
 #use lib '/usr/lib/perl5/vendor_perl/5.8.8.pm';
############################################# INIZIO SCRIPT##############################

#####inizializzazione parametri di simulazione
	$db=new Db("db.db");
	$plotter=new Plotter();
	$parameters=new Parameters("db.db");
	print "Nr.of output neurons: ";$nr_output_neurons=<STDIN>;chomp $nr_output_neurons;
	print "Id time series: ";$id_series=<STDIN>;chomp $id_series;
	print "Id variable: "; $variable=<STDIN>;chomp $variable;
	print "Nr.of predictions: "; $nr_of_predictions=<STDIN>;chomp $nr_of_predictions;
	print "\nTotal nr.of quotes: " . $db->getNrPeriods($id_series, $variable);
	print "Max value: " . $db->getMax($id_series, $variable);
	print "Min value: " . $db->getMin($id_series, $variable);
	print "Mean: " . $db->getMean($id_series, $variable);
	
#####calcolo dei parametri della rete neurale artificiale
	print "\n\nCalculating neural net parameters and outputs...";
	@predictions=$parameters->calcMPerceptronParam($id_series,$variable,$nr_output_neurons,$nr_of_predictions);
	
#####ultime 5 quotazioni della serie storica
	@quotes=$db->getLatestQuotes($id_series, $variable, 5);
	for($qts=0;$qts<4;$qts++){	
		sleep(0.5);
		print "Time series element t" . ($qts-3) . ": @quotes[3-$qts]";
	}

#####stampa delle previsioni
	for($fcst=0;$fcst<$nr_of_predictions;$fcst++){	
		sleep(0.5);
		$value=0;
		$value=int(@predictions[$fcst]*1000)/1000;
		print "Model t" . ($fcst+1) . ": $value\n";
	}

#####plotting delle previsioni su piano cartesiano
	$plotter->plot(@predictions);


