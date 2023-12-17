#!/usr/bin/perl 
####################################
package Db;
####################################
sub new
{
    my $class = shift;
    my $self = {
        _Db => shift, #il costruttore prende in ingresso il nome del db (es. "db.db")
    };
    # Print all the values just for clarification.
    bless $self, $class;
}

#nr di periodi della simulazione in esame
sub getNrPeriods {
    my( $self, $id_series) = @_;
	return `sqlite3 $self->{_Db} "select max(time) from Data where id_series=$id_series;"`;
	}

#massimo valore serie storica	
sub getMax {
	my( $self, $id_series, $variable) = @_;
	return `sqlite3 $self->{_Db} "select max($variable) from Data where id_series=$id_series;"`;
	}

#minimo valore serie storica	
sub getMin {
	my( $self, $id_series, $variable) = @_;
	return `sqlite3 $self->{_Db} "select min($variable) from Data where id_series=$id_series;"`;
	}

#valore medio serie storica	
sub getMean {
	my( $self, $id_series, $variable) = @_;
	$nr_of_quotes=`sqlite3 $self->{_Db} "select max(time) from Data where id_series=$id_series;"`;
	$sum_of_quotes=`sqlite3 $self->{_Db} "select sum($variable) from Data where id_series=$id_series;"`;
	$mean=int($sum_of_quotes/$nr_of_quotes);
	return $mean;
	}

#ultimi valori della serie storica
sub getLatestQuotes {
    my( $self, $id_series, $id_var, $nr_of_quotes ) = @_;
	return `sqlite3 $self->{_Db} "select $id_var from Data where id_series=$id_series order by time desc limit $nr_of_quotes;"`;
}#fine metodo
	
1;

#############################
package Parameters;
#############################
sub new
{
    my $class = shift;
    my $self = {
	 _Db => shift, #il costruttore prende in ingresso il nome del db (es. "db.db")
    };
    # Print all the values just for clarification.
    bless $self, $class;

}

sub calcMPerceptronParam{
	my( $self, $id_series, $var, $nr_output_neurons, $nr_of_predictions) = @_;
	
	use List::Util qw(max);
	use Data::Dumper qw(Dumper);
	
	$nr_of_output_neurons=$nr_output_neurons;
	$nr_of_hidden_neurons=10;
	$nr_of_input_neurons=5;
	$places=2;
	$factor=10**$places;

	######### inizializza il vettore di inputs. 
	#la regola generale è che più sono le quotazioni più è probabile trovare la soluzione ottimale.
	#Fare esperimenti per raggiungere il giusto tradeoff tra tempo di convergenza verso l'optimum
	#e accuratezza del forecasting, senza esagerare con la velocità di convergenza 
	#controllata dal parametro $r, perchè fa sballare tutto.
	
	$training_size=80; #dimensione del training-set in % sul totale delle quote
	@training_quotes=`sqlite3 $self->{_Db} "select $var from Data where id_series=$id_series limit ((select count($var) from Data where id_series=$id_series)*$training_size/100);"`;
	@test_quotes=`sqlite3 $self->{_Db} "select $var from Data where id_series=$id_series and id_data>(select count($var) from Data where id_series=$id_series)*$training_size/100;"`;
	@total_quotes=`sqlite3 $self->{_Db} "select $var from Data where id_series=$id_series;"`;
	$nr_of_training_quotes=scalar @training_quotes;
	$nr_of_total_quotes=scalar @total_quotes;
	$nr_of_test_quotes=scalar @test_quotes;
	$max_total_quotes=max(@total_quotes);
	$max_training_quotes=max(@training_quotes);
	$inizio_test=(`sqlite3 $self->{_Db} "select count($var)*$training_size/100 from Data where id_series=$id_series;"`)-5;
	
	@quotes=@training_quotes;
	#normalizzazione dei valori di quotazione (velocizza i calcoli)
		 for ($i=0;$i < $nr_of_training_quotes;$i++){
				$normalized=@quotes[$i]/$max_training_quotes;
				@quotes[$i]=$normalized;
				}

	######### inizializza stocasticamente i pesi dei neuroni di output e hidden
	##output
		my @output_neurons : shared;
		for($i=0;$i<$nr_of_output_neurons;$i++){
			my @addon : shared=();
			for($n=0;$n<($nr_of_hidden_neurons+1);$n++){
			@addon[$n]=rand(0.001);
			}
			push(@output_neurons, \@addon);#il backslash serve ad aggiungere a @output_neuron, come unica variabile, tutte le variabili di @ddon
		}

	##hidden
		my @hidden_neurons : shared;
		for($i=0;$i<$nr_of_hidden_neurons;$i++){
			my @addon : shared=();
			for($n=0;$n<6;$n++){ #6 pesi: 5 quotazioni + 1 bias
			@addon[$n]=rand(0.001);
			}
			push(@hidden_neurons, \@addon);#il backslash serve ad aggiungere a @hidden neurons, come unica variabile, tutte le variabili di @ddon
		}

	######### ADDESTRAMENTO RETE NEURALE
	
	$max_err=0.06; #errore massimo, occorre fare degli esperimenti sulla serie di test per trovare l'ottimale
	$r=0.1;	#tasso di apprendimento	
	#Il tasso di apprendimento oscilla teoricamente tra 0 e 0.9.
	#Se il tasso di apprendimento è troppo alto i pesi stimati potrebbero oscillare moltissimo
	#e in modo non lineare, con numeri molto alti o molto bassi.
	#Purtroppo perl quando raggiunge certi numeri restituisce NaN (not a number) o Inf.
	#Quindi è opportuno settare un parametro di apprendimento molto basso per evitare questo, ma non eccessivamente
	#basso perchè altrimenti i pesi non convergono abbastanza velocemente verso la soluzione ottimale
		
	my $inizio : shared=0;
	my $fine : shared=5;
	my $sample : shared=1;

	for($fine=5;$fine<scalar @quotes;$fine++){
			@hidden_activations=(); #è il potenziale sinaptico calcolato come somma pesata degli input + bias
			@hidden_transfers=(); #funzione di trasferimento o attivazione logistica, calcolata come funzione del potenziale sinaptico
			@output_activations=(); 
			@output_transfers=();
			@output_errors=(); #output del neurone - valore reale
			@output_deltas=(); #errore_output*(derivata dell'errore rispetto al peso)
			@hidden_errors=(); #somma di 'output_deltas'*peso_di_output di tutti i neuroni di output
			@hidden_deltas=(); #errore_hidden*(derivata dell'errore rispetto al peso)
		
		do {
				$attivazione_input1=0;
				$attivazione_input2=0;
				$attivazione_input3=0;
				$attivazione_input4=0;
				$attivazione_input5=0;
				$neper=2.7182818284590452353602;
				@hidden_activations=();
				@hidden_transfers=();
				@output_activations=();
				@output_transfers=();
				@output_errors=();
				@output_deltas=();
				@hidden_errors=();
				@hidden_deltas=();
				$output_average_error_total=0;
				$hidden_average_error_total=0;
				$sum_of_output_errors=0;
				$sum_of_hidden_errors=0;

				######### calcolo degli outputs di ogni neurone (funzioni di attivazione e trasferimento)	
				#la rete in esame calcola il trasferimento solo sul potenziale sinaptico dei neuroni hidden	e di quello di output

				#strato inputs
				$attivazione_input1=@quotes[$inizio];
				$attivazione_input2=@quotes[$inizio+1];
				$attivazione_input3=@quotes[$inizio+2];
				$attivazione_input4=@quotes[$inizio+3];
				$attivazione_input5=@quotes[$inizio+4];

				#strato hidden
				for($h=0;$h<$nr_of_hidden_neurons;$h++){
				@hidden_activations[$h]=$hidden_neurons[$h][0]*$attivazione_input1+
									$hidden_neurons[$h][1]*$attivazione_input2+
									$hidden_neurons[$h][2]*$attivazione_input3+
									$hidden_neurons[$h][3]*$attivazione_input4+
									$hidden_neurons[$h][4]*$attivazione_input5+
									$hidden_neurons[$h][5]*1;#bias

				@hidden_transfers[$h]=1/(1+$neper**(-@hidden_activations[$h]));
				}


				#strato output
				for($o=0;$o<$nr_of_output_neurons;$o++){
					@output_activations[$o]=@hidden_transfers[0]*$output_neurons[$o][0]+	
									@hidden_transfers[1]*$output_neurons[$o][1]+
									@hidden_transfers[2]*$output_neurons[$o][2]+
									@hidden_transfers[3]*$output_neurons[$o][3]+
									@hidden_transfers[4]*$output_neurons[$o][4]+
									@hidden_transfers[5]*$output_neurons[$o][5]+
									@hidden_transfers[6]*$output_neurons[$o][6]+
									@hidden_transfers[7]*$output_neurons[$o][7]+
									@hidden_transfers[8]*$output_neurons[$o][8]+
									@hidden_transfers[9]*$output_neurons[$o][9]+
									1*$output_neurons[$o][10];#bias
					@output_transfers[$o]=1/(1+$neper**(-@output_activations[$o]));	
					}												

				######### BACKPROPAGATION - Calcolo degli errori e dei delta di ogni neurone
				#strato outputs
				for($i=0;$i<$nr_of_output_neurons;$i++){
					@output_errors[$i]=@output_transfers[$i]-@quotes[$inizio+5]; #posso anche invertire il valore stimato e quello desiderato, ma a questo punto, come avvenuto per il perceptron, devo mettere il segno + nella formula del ricalcolo dei pesi
					@output_deltas[$i]=@output_errors[$i]*@output_transfers[$i]*(1-@output_transfers[$i]); #dell'equazione finale di modifica del peso 'deltas' è il prodotto tra l'errore e la derivata prima della funzione di attivazione (logistica) 
				}
				#print "@output_errors[0] = (@output_activations[0])@output_transfers[0] - @quotes[$inizio+5]\n";

				#strato hidden
				for($h=0;$h<$nr_of_hidden_neurons;$h++){

					for($i=0;$i<$nr_of_output_neurons;$i++){
						@hidden_errors[$h]=@hidden_errors[$h]+@output_deltas[$i]*$output_neurons[$i][$h]; #si tiene conto dell'errore compiuto su tutti i neuroni di output. Questo errore (passato attraverso la funzione delta) viene riproposto 'r' volte sul peso, sulla base del tasso di apprendimento
					}

					@hidden_deltas[$h]=@hidden_errors[$h]*@hidden_transfers[$h]*(1-@hidden_transfers[$h]);

				}

				######### ricalcolo i pesi dei neuroni (riduco il gradiente cioè la derivata dell'errore rispetto ai pesi neurali)
				#strato output
				for($o=0;$o<$nr_of_output_neurons;$o++){
					for($w=0;$w<$nr_of_hidden_neurons;$w++){
						$output_neurons[$o][$w]=$output_neurons[$o][$w]-$r*@output_deltas[$o]*@hidden_transfers[$w];
					}
				$output_neurons[$o][$nr_of_hidden_neurons]=$output_neurons[$o][$nr_of_hidden_neurons]-$r*@output_deltas[$o]*1; #bias
				}

				#strato hidden
				for($h=0;$h<$nr_of_hidden_neurons;$h++){
					for($w=0;$w<$nr_of_input_neurons;$w++){
						$hidden_neurons[$h][$w]=$hidden_neurons[$h][$w]-$r*@hidden_deltas[$h]*@quotes[$inizio+$w];
					}
				$hidden_neurons[$h][$nr_of_input_neurons]=$hidden_neurons[$h][$nr_of_input_neurons]-$r*@hidden_deltas[$h]*1; #bias
				}	
				
				#calcolo dell'errore medio di tutti i neuroni sia di output che hidden
				for($i=0;$i<$nr_of_output_neurons;$i++){
				$sum_of_output_errors=$sum_of_output_errors+@output_errors[$i];
				}
				for($h=0;$h<$nr_of_hidden_neurons;$h++){
				$sum_of_hidden_errors=$sum_of_hidden_errors+@hidden_errors[$i];
				}
				$output_average_error=$sum_of_output_errors/$nr_of_output_neurons;
				$hidden_average_error=$sum_of_hidden_errors/$nr_of_hidden_neurons;
				$output_average_error=abs($output_average_error);
				$hidden_average_error=abs($hidden_average_error);
				#print "$output_average_error\n";

		} while($output_average_error > $max_err or $hidden_average_error > $max_err ); 

		$inizio=$inizio+1;
		$sample=$sample+1;

	}#inizio del sample di addestramento successivo
	print "done";

	######### VALIDAZIONE RETE NEURALE - calcolo dell'errore assoluto medio sul test set
	if($training_size<100){
	@errore_predizione=();
	$sum_errori_predizione=0;
	for($iii=0;$iii<scalar @test_quotes;$iii++){
			@hidden_activations=();
			@hidden_transfers=();
			@output_activations=();
			@output_transfers=();	
			$average_forecast=0;
			$sum_forecasts=0;
			
				#strato inputs
				$attivazione_input1=@total_quotes[$inizio_test]/$max_total_quotes; 
				$attivazione_input2=@total_quotes[$inizio_test+1]/$max_total_quotes;
				$attivazione_input3=@total_quotes[$inizio_test+2]/$max_total_quotes;
				$attivazione_input4=@total_quotes[$inizio_test+3]/$max_total_quotes; 
				$attivazione_input5=@total_quotes[$inizio_test+4]/$max_total_quotes; 

				#strato hidden
				for($h=0;$h<$nr_of_hidden_neurons;$h++){
				@hidden_activations[$h]=$hidden_neurons[$h][0]*$attivazione_input1+
									$hidden_neurons[$h][1]*$attivazione_input2+
									$hidden_neurons[$h][2]*$attivazione_input3+
									$hidden_neurons[$h][3]*$attivazione_input4+
									$hidden_neurons[$h][4]*$attivazione_input5+
									$hidden_neurons[$h][5]*1;#bias

				@hidden_transfers[$h]=1/(1+$neper**(-@hidden_activations[$h]));
				}


				#strato output
				for($o=0;$o<$nr_of_output_neurons;$o++){
					@output_activations[$o]=@hidden_transfers[0]*$output_neurons[$o][0]+	
									@hidden_transfers[1]*$output_neurons[$o][1]+
									@hidden_transfers[2]*$output_neurons[$o][2]+
									@hidden_transfers[3]*$output_neurons[$o][3]+
									@hidden_transfers[4]*$output_neurons[$o][4]+
									@hidden_transfers[5]*$output_neurons[$o][5]+
									@hidden_transfers[6]*$output_neurons[$o][6]+
									@hidden_transfers[7]*$output_neurons[$o][7]+
									@hidden_transfers[8]*$output_neurons[$o][8]+
									@hidden_transfers[9]*$output_neurons[$o][9]+
									1*$output_neurons[$o][10];#bias
					@output_transfers[$o]=1/(1+$neper**(-@output_activations[$o]));	
					$sum_forecasts=$sum_forecasts+@output_transfers[$o];
					}							
					$average_forecast=$sum_forecasts/$nr_of_output_neurons;
					$average_forecast=$average_forecast*$max_total_quotes; #rinormalizzazione della quotazione
					$average_forecast=int($average_forecast*100)/100;		
					
					@errore_predizione[$iii]=abs($average_forecast-@test_quotes[$iii]);
					$sum_errori_predizione=$sum_errori_predizione+@errore_predizione[$iii];
					#print "\nprevisione: $average_forecast";
					#print "\ndato_reale: @test_quotes[$iii]";
					#print "errore predizione $iii: @errore_predizione[$iii]\n";

				$inizio_test=$inizio_test+1;

	}
	$errore_medio_predizione=$sum_errori_predizione/$nr_of_test_quotes;
	$errore_medio_predizione=int($errore_medio_predizione*100)/100;
	print "\nMAE on test_set: $errore_medio_predizione\n\n";
	}
	
	######### PREDIZIONE RETE NEURALE a n periodi nel futuro

	@average_predictions=();
	for($ind2=0;$ind2<5;$ind2++)
	{
		@latest_quotes[$ind2]=@total_quotes[scalar @total_quotes-5+$ind2]/$max_total_quotes;
	}
	@appoggio=@latest_quotes;	
	
	for($fcst=0;$fcst<$nr_of_predictions;$fcst++){
	@hidden_activations=();
	@hidden_transfers=();
	@output_activations=();
	@output_transfers=();	
	$sum_forecasts=0;
	$average_forecast=0;
		#strato input
			$attivazione_input1=@latest_quotes[0]; #più antico
			$attivazione_input2=@latest_quotes[1];
			$attivazione_input3=@latest_quotes[2];
			$attivazione_input4=@latest_quotes[3];
			$attivazione_input5=@latest_quotes[4]; #più recente
		#strato hidden
		for($h=0;$h<$nr_of_hidden_neurons;$h++){
			@hidden_activations[$h]=$hidden_neurons[$h][0]*$attivazione_input1+
									$hidden_neurons[$h][1]*$attivazione_input2+
									$hidden_neurons[$h][2]*$attivazione_input3+
									$hidden_neurons[$h][3]*$attivazione_input4+
									$hidden_neurons[$h][4]*$attivazione_input5+
									#rand(); #bias stocastico puro
									$hidden_neurons[$h][5]*(0.9+rand()*0.2); #bias semi-deterministico (prende una frazione del bias fino ad incrementarlo o decrementarlo del 10%)
									#$hidden_neurons[$h][5]*1;#bias deterministico
			
			@hidden_transfers[$h]=1/(1+$neper**(-@hidden_activations[$h]));	
			
			}

		#strato output
		$sum_forecasts=0;
		for($o=0;$o<$nr_of_output_neurons;$o++){
			@output_activations[$o]=@hidden_transfers[0]*$output_neurons[$o][0]+	
							@hidden_transfers[1]*$output_neurons[$o][1]+
							@hidden_transfers[2]*$output_neurons[$o][2]+
							@hidden_transfers[3]*$output_neurons[$o][3]+
							@hidden_transfers[4]*$output_neurons[$o][4]+
							@hidden_transfers[5]*$output_neurons[$o][5]+
							@hidden_transfers[6]*$output_neurons[$o][6]+
							@hidden_transfers[7]*$output_neurons[$o][7]+
							@hidden_transfers[8]*$output_neurons[$o][8]+
							@hidden_transfers[9]*$output_neurons[$o][9]+
							#rand(); #bias stocastico puro
							$output_neurons[$o][10]*(0.9+rand()*0.2); #bias semi-deterministico (prende una frazione del bias fino ad incrementarlo o decrementarlo del 10%)
							#1*$output_neurons[$o][10];#bias deterministico
			@output_transfers[$o]=1/(1+$neper**(-@output_activations[$o]));	
			$sum_forecasts=$sum_forecasts+@output_transfers[$o];
			}

			$average_forecast=$sum_forecasts/$nr_of_output_neurons;
	#scorrimento dell'array contenente le ultime quotazioni, in modo tale da inserire l'ultima predizione come nuovo dato

			for($indx=0;$indx<scalar @latest_quotes-1;$indx++){	
				@latest_quotes[$indx]=@appoggio[$indx+1];
			}
			@latest_quotes[4]=$average_forecast;

			@appoggio=();@appoggio=@latest_quotes;
			$average_forecast=$average_forecast*$max_total_quotes; #rinormalizzazione della quotazione
			$average_forecast=int($average_forecast*10000000)/10000000;
	#popolamento array di output
	@average_predictions[$fcst]=$average_forecast;
	}
	
	return @average_predictions;
}#fine metodo

1;

#############################
package Plotter;
#############################
use Tk;
use Tk::PlotDataset;
use Tk::LineGraphDataset;

sub new
{
    my $class = shift;
    my $self = {
	};
    bless $self, $class;

}

sub plot{
	my($self, @predictions) = @_;

	
	@datay=@predictions;
	
	my $main_window = MainWindow -> new;
	
	my $dataset1 = LineGraphDataset -> new
	(
	-name => 'currency',
	-yData => \@datay,
	-color => 'blue'
	);

	my $graph = $main_window -> PlotDataset
	(
	-width => 700,
	-height => 500,
	-background => 'snow'
	) -> pack(-fill => 'both', -expand => 1);

	$graph -> addDatasets($dataset1);
	$graph -> plot;

	MainLoop;
	
}#fine metodo

1;
