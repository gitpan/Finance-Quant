# Data/Dumper.pm
#
# convert perl data structures into perl syntax suitable for both printing
# and eval
#
# Documentation at the __END__
#

package Finance::Quant;
use strict;
use warnings;
no warnings 'redefine';
no warnings 'utf8';
use File::Find; 

#my($recurse  $name  $case $linenums $quick_start  $use_regex  $linenums  $textbuffer  $seeking  $cancel  $f1_label  $textbuffer  $entry  $seeking)

use vars qw/$VERSION @directories @DATA %files $current @symbols $textbuffer $textview $dir $sources/;

$VERSION = 0.01;

                                
require Exporter;
use  WWW::Mechanize; 
use Carp;
use Data::Dumper;
use File::Spec::Functions;
use File::Path;
use Time::Local;
use File::Fetch;
use File::Copy;
use Finance::Optical::StrongBuy;
use HTML::TreeBuilder;
use Text::Buffer;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw/Homex/;

our @directories = qw(download ibes-strong-buy ratings symbols charts);

our %files;                                               
our $current="Finance-Quant";      
our ($recurse, $name, $case,$linenums,$quick_start, $use_regex,$seeking,$textbuffer,$textview,$cancel) =(1,1,1,1,1,1,1,undef,undef); ##< patch  

our $sources = {
      TIME_SALES           => "http://www.nasdaq.com/symbol/%s/time-sales",
      RT_QUOTE             => "http://www.nasdaq.com/symbol/%s/real-time",
      NASDAQ_SYMBOLS       => "ftp://ftp.nasdaqtrader.com/symboldirectory/nasdaqlisted.txt",
      NASDAQ_COMMUNITY     => "http://community.nasdaq.com/community-ratings.aspx?stockticker=%s&AllRatings=1",
      IBES_ICON            => "http://content.nasdaq.com/ibes/%s_Smallcon.jpg",
      IBES_RECOMMENDATIONS => "http://www.nasdaq.com/symbol/%s/recommendations",
      IBES_ANALYST         => "http://www.nasdaq.com/symbol/%s/analyst-research",
      NASDAQ_SYMBOLS       => "http://chart.finance.yahoo.com/z?s=%s&t=3m&q=c&l=on&z=l&p=b,p,v,m20&a=m26-12-9&lang=en-US&region=US"
    };
                    

## ACTIVATE FLAGS AND ERASE THEM FROM @ARGV... 
 
if( grep{/\bn\b/} @ARGV ){@ARGV = grep { $_ ne 'n' } @ARGV; $name = 1 }; 
if( grep{/\br\b/} @ARGV ){@ARGV = grep { $_ ne 'r' } @ARGV; $recurse = 1 }; 
if( grep{/\bR\b/} @ARGV ){@ARGV = grep { $_ ne 'R' } @ARGV; $use_regex = 1 }; ##<patch 
if( grep{/\bc\b/} @ARGV ){@ARGV = grep { $_ ne 'c' } @ARGV; $case = 1 }; 

 
$linenums = 1; #opened file line numbering is on by default 
my $search_str = $ARGV[0] or $quick_start = 1; 
$search_str ||= undef; 

our $dir = File::Spec->tmpdir();

chdir($dir) if (defined($dir) and -d $dir); 
chdir($current) if (defined($current) and -d $current); 
1;

sub recommended {
    my $class = shift;

    my $config = {};
    
    my $self = $class->new($config);

       
       $self->{config}->{'ibes'} = {SP500=>1,NYSE=>0,AMEX=>0,NASDAQ=>0,CUSTOM=>1},
       $self->{config}->{'sector-data'}         = 1;
       $self->{config}->{'markets'}             = 1;
       $self->{config}->{'yahoo-charts'}        = 1;
       $self->{config}->{'historic-csv'}        = 1;
       $self->{config}->{'nasdaq-user-rating'}  = 1;
       $self->{config}->{'nasdaq-guru-rating'}  = 1;



    $self->createDataDir();

    $self->_init();

    return $self;

}


sub _init{

    my $self = shift;

    $self->{sources} = $sources;

    
    my @DATA = grep { if($_ =~ /=(.*)=(.*)/) {$_=[$1,$2];} } <DATA>;



    foreach(@DATA){
      
      if(defined($self->{config}->{'ibes'}->{$_->[0]}) &&
         $self->{config}->{'ibes'}->{$_->[0]} == 1)  {
         $self->{config}->{'ibes'}->{$_->[0]} = $_->[1];

         if($_->[0] eq "NASDAQ"){
            $self->{config}->{'ibes'}->{NASDAQ}=sprintf $self->getNasdaqSymbols(File::Spec->tmpdir(),"ftp://ftp.nasdaqtrader.com/symboldirectory/nasdaqlisted.txt");
         }

      }
    }
    
   
    
    $self->{'sector-summary'} = {
        summary=>[Finance::Google::Sector::Mean::sectorsummary()],
        quotes=>[Finance::NASDAQ::Markets::sector()]
    } unless(!$self->{config}->{'sector-data'});
    
    $self->{'indices'} =  {
        quotes=>[Finance::NASDAQ::Markets::index()]
    }unless(!$self->{config}->{'markets'});
       


}

sub new {
    my $class = shift;
    my $symbol = shift;

    croak "need a symbol! perhaps you should use Finance::Quant->recommended" unless($symbol);

    

    
    my $self = bless {
        
        config=>{'ibes'=>{CUSTOM=>$symbol}},
        optical=>Finance::Optical::StrongBuy->new("."),
        
    }, $class;


#
#


$self->{config}->{sources} = {
      TIME_SALES           => "http://www.nasdaq.com/symbol/%s/time-sales",
      RT_QUOTE             => "http://www.nasdaq.com/symbol/%s/real-time",
      NASDAQ_SYMBOLS       => "ftp://ftp.nasdaqtrader.com/symboldirectory/nasdaqlisted.txt",
      NASDAQ_COMMUNITY     => "http://community.nasdaq.com/community-ratings.aspx?stockticker=%s&AllRatings=1",
      IBES_ICON            => "http://content.nasdaq.com/ibes/%s_Smallcon.jpg",
      IBES_RECOMMENDATIONS => "http://www.nasdaq.com/symbol/%s/recommendations",
      IBES_ANALYST         => "http://www.nasdaq.com/symbol/%s/analyst-research",
      NASDAQ_SYMBOLS       => "http://chart.finance.yahoo.com/z?s=%s&t=3m&q=c&l=on&z=l&p=b,p,v,m20&a=m26-12-9&lang=en-US&region=US"
    };
                    

    $self->{config}->{'nasdaq-guru-rating'}  = 1;

    $self->{textbuffer} = new Text::Buffer(-file=>'my.txt');
    

    return $self;
}



sub getNasdaqSymbols {

  my $this = shift;
  my $dir  = shift;
  my $url = shift;

  
    if( defined $dir ) {
          
        my $ff = File::Fetch->new(uri => $url);

        my $where =  $ff->fetch( to =>$dir);

        return $this->symClean($where);
        
    }else{
        croak "need a working directory";
    }

}

sub get_source_image {

  my($this)= shift;
  my ($json_url) = @_;
  my $EXIT_CODE = 1;
  my $content = "";
  
  my $browser = WWW::Mechanize->new(
          stack_depth     => 0,
          timeout         => 3,
          autocheck       => 0,
  );
  $browser->get( $json_url );

  if ( $browser->success( ) ) {
    $EXIT_CODE=0;
  } else {
    $EXIT_CODE=1;
  }


  $content = $browser->content() unless($EXIT_CODE);

  return $content;
}

sub writeFile  {

  my($this)= shift;
  my ($raw,$file) = @_;

  return unless($raw);

  open(OUT, '>', $file);
  binmode OUT;
  print OUT $raw;
  close(OUT);

}


sub Download{
  my $this = shift;
  my $symbols = shift;

  croak "end no symbols!!!" if !defined($symbols);
  
  

  $this->{optical}->set_path(".");

    foreach my $symbol (split(" ",$symbols)) {
        $this->{optical}->callCheck($symbol);
    }
    
    return $this->{optical};
        
}


sub createDataDir {


  my $self = shift;
  my $config = $self->{config};
  my $dir = File::Spec->tmpdir();
  my $date = gmtime;
  my @e = split " ",$date;# =~ s/ /_/g;
  my $downfolder = "$e[4]-$e[1]-$e[2]-$e[0]";
  
  $self->{today}->{$dir}->{$downfolder} = [@directories];  
  $self->{date} = $date;
   
    if( defined $dir ) {
        	

        chdir($dir);

        File::Path::mkpath($current);

        chdir($current);
        File::Path::mkpath($downfolder);
       
        chdir($downfolder);

	
        File::Path::mkpath(@directories, {
                 verbose => 1,
                 mode => 0711,
             } );


        chdir($downfolder);
        chdir("download");
  }

}



sub Home {

  
  my $self = shift;
  

  my $config = $self->{config};


  
    
  my $dir = File::Spec->tmpdir();
  my $date = gmtime;
  my @e = split " ",$date;# =~ s/ /_/g;
  my $downfolder = "$e[4]-$e[1]-$e[2]-$e[0]";
  


  $self->{today}->{$dir}->{$downfolder} = [@directories];  
  $self->{date} = $date;
   
    if( defined $dir ) {
        	

        chdir($dir);

        File::Path::mkpath($current);

        chdir($current);
        File::Path::mkpath($downfolder);
       
        chdir($downfolder);

	
        File::Path::mkpath(@directories, {
                 verbose => 1,
                 mode => 0711,
             } );


          #$self->{NYSE}->{timer}=time;

          

         
        my $all =  {};
        chdir($downfolder);
        chdir("download");




        foreach(keys %{$self->{config}->{ibes}}) {
          
            $self->Download($self->{config}->{ibes}->{$_});

       }

      chdir("..");

    
    my @ok = keys %{$self->{optical}->{'result'}};


    my $ff = undef;

    $self->{'result'}->{symbols} = [@ok];
    
    foreach my $sym (@ok) {


        $ff = $self->get_source_image(sprintf("http://community.nasdaq.com/community-ratings.aspx?stockticker=%s&AllRatings=1",$sym));
        
        if($ff =~ /<b>(.*)ratings<\/b>/){
          $self->writeFile($1,sprintf( "ratings/%s.html",$sym ));
          $self->{'result'}->{$sym}->{'nasdaq-userrating'}=$1;
        }
            
        $self->{'result'}->{$sym}->{'nasdaq-guru'}=[$self->getguruscreener($sym )];
      
        $ff = $self->get_source_image(sprintf("http://content.nasdaq.com/ibes/%s_Smallcon.jpg",$sym ));
        $self->writeFile($ff,sprintf("ibes-strong-buy/%s.jpg",$sym ));

        $ff = $self->get_source_image(sprintf("http://chart.finance.yahoo.com/z?s=%s&t=3m&q=c&l=on&z=l&p=b,p,v,m20&a=m26-12-9&lang=en-US&region=US",$sym ));
        $self->writeFile($ff,sprintf("charts/%s.png",$sym ));
        $self->{$dir}->{$downfolder}->{'charts'}->{$sym}= sprintf("%s/%s/%s/charts/%s.png",$dir,$current,$downfolder,$sym);
                

        
    }

    

    chdir("..");

   }else{
        croak "need a working directory";
    }

    

    return $self;
}


sub getguruscreener {

 my $self = shift;
    my $symbol = shift;
    my $temp = undef;
    my $url = sprintf("http://www.nasdaq.com/symbol/%s/guru-analysis",$symbol);
    my @ids = qw/guru/;
    my $content =  $self->get_source_image($url);
    my %out = ();
    my %collection = ();
    return unless defined $content;

 my $tree = HTML::TreeBuilder->new;
    $tree->parse($content);

  my @ret = grep {

  if($_ =~ />(.*)</) {

      my $out =$1;
      if(defined($out) && length $out>40){
          $out=~ s/<\/tr>|<\/td>|<\/table>|<td*>|<tr*>|<tr>|<td>|<\/a>/\n/g;
          $out=~/<h2>(.*)<\/h2>(.*)<\/b/;
          my ($methode,$pct) = ($1,$2);

          if(defined($symbol) && defined($pct)){
            $pct =~ s/$symbol gets a <b>//g unless(!$symbol);
          }
          if(defined($methode) &&
            defined($pct) &&
            $methode =~ m/Investor/){
            my @set = split("Investor",$methode);
            $_={'methode'=>$set[0],'pct'=>$pct,"author"=>$set[1]};

          }
      }
  } } split("guru(.*)Detailed Analysis",$content);

  $tree = $tree->delete();

  return @ret;



}

sub symClean {
  
    
  my $self = shift;
  my $list = shift;
  
  my $c = 0;
  open FILE,$list or croak $!;     
  my @lines = <FILE>;

    foreach my $line(@lines){
        
        next if($line =~/File Creation Time|Symbol\|Security Name/);
        
        $line =~ /(.*?)\|/;

        if(defined($1)){       
            push @symbols,$1;#sprintf(",(\"%s\")",$1);
            #print $1,($c % 100 ? "\n":" ");
        }
    
    }
    my $query = sprintf("%s", join(" ",@symbols));
    return $query;
    #return @symbols;

}
    
    
sub do_file_search 
{ 
 

  my $self = shift;
  my $file = shift;
  
  if( ! defined $file ){return} 
 
  my @lines = (); 
 
    foreach my $aref( @{$files{$file}} ) 
    { 
           push @lines, $$aref[0]; 
    } 
 
  $self->{textbuffer}->insert(''); 
 
  open (FH,"< $file"); 
  while(<FH>){ 
     my $line = $.; 
 
     if($linenums) 
     { 
       my $lineI = sprintf "%03d", $line; 
       $self->{textbuffer}->insert_with_tags_by_name ($self->{textbuffer}->get_end_iter, $lineI, 'rmap'); 
       $self->{textbuffer}->insert ($self->{textbuffer}->get_end_iter, ' '); 
     } 
 
    if( grep {/^$line$/} @lines ) 
    { 
           $self->{textbuffer}->insert_with_tags_by_name ($self->{textbuffer}->get_end_iter, $_, 'rmapZ'); 
    } 
    else 
    { 
          $self->{textbuffer}->insert_with_tags_by_name ($self->{textbuffer}->get_end_iter, $_, 'bold'); 
    } 
  } 
 close FH; 
 
#set up where to scroll to when opening file 
 
 my $first; 
 if ( $lines[0] > 0 ){ $first = $lines[0] }else{$first = 1} 
 
#set frame label to file name 
 
$self->{textbuffer}->insert($file); 
 
$current = $file; 
} 
################################################################ 
 
sub do_dir_search 
{ 
 my $self = shift;

my $search_str = shift;
 
$seeking = 1; 
$cancel = 0; 
 
 
%files = (); 

$self->{textbuffer}->append('Search Results'); 
$self->{textbuffer}->append($search_str); 

 
my $path = '.'; 
 

if( ! length $search_str){$seeking = 0; $cancel = 0; return} 
 
my $regex;  #defaults to case insensitive 
 
#if ($case){$regex =  qr/\Q$search_str\E/} 
#      else{$regex =  qr/\Q$search_str\E/i} ##< before 
if ($case)                                       ##<-------+ 
{                                                           # 
   if ($use_regex)                                          # 
   {                                                        # 
     $regex =  qr/$search_str/;                             # 
   }                                                        # 
   else                                                     # 
   {                                                        # 
       $regex =  qr/\Q$search_str\E/                        # 
   }                                                        # patch 
}                                                           # (regex) 
else                                                        # 
{                                                           # 
   if ($use_regex)                                          # 
   {                                                        # 
     $regex =  qr/$search_str/i;                            # 
   }                                                        # 
   else                                                     # 
   {                                                        # 
       $regex =  qr/\Q$search_str\E/i;                      # 
   }                                                        # 
}                                                ##<-------+ 


#$self->{textbuffer}->append($regex); 

# use s modifier for multiline match 
 
my $count = 0; 
my $count1 = 0; 
 
find (sub { 
      if( $cancel ){ return $File::Find::prune = 1} 
      $count1++; 
      if( ! $recurse ){ 
      my $n = ($File::Find::name) =~ tr!/!!; #count slashes in file 
      return $File::Find::prune = 1 if ($n > 1); 
      } 
     return if -d; 
     return unless (-f);#and -T); 
 
    if($name){ 
          if ($_ =~ /$regex/){ 
	     push @{$files{$File::Find::name}}, [-1,'']; #push into HoA 
	  } 
     } 
    else 
    { 
         open (FH,"< $_"); 
            while(<FH>) 
            { 
               if ($_ =~ /$regex/) 
               { 
	           chomp $_;
             
                   push @{$files{$File::Find::name}}, [$., $_]; #push into HoA 
     	       } 
	     } 
	 close FH; 
     } 
#------ 
        my $key = $File::Find::name; 
 
        if( defined  $files{$key} ) 
        { 
           $count++; 
    	   my $aref = $files{$key}; 
	   my @larray = @$aref; 

            $self->{textbuffer}->append("$key"); 

 
         foreach my $aref(@larray) 
         { 
	    if( $$aref[0] > 0 ) { 
        my $lineI = sprintf"%03d", $$aref[0];

        $self->{textbuffer}->append("\n". $lineI); 
            
	     } 
	  } 
       
       } 
      # $self->{textbuffer}->append(""); 
       
 
 
 #----- 
 
    }, $dir); 
 
     $self->{textbuffer}->append("$count1 checked -- $count matches .. DONE"); 
     $seeking = 0; 
     $cancel = 0; 

    return [$self->{textbuffer}];
} 
 
############################################################################## 
 
sub insert_link 
{ 
  my $self = shift;
  my ($buffer, $file ) = @_; 
 
  #create tag here independently, so we can piggyback unique data 
 
  my $tag = $buffer->create_tag (undef, 
				 foreground => "blue", 
				 underline => 'single', 
				 size   => 20 * 1
				 ); 
 
# piggyback data onto each tag 
 
  $tag->{file} = $file; 
  
 
} 
 
########################################################################### 
# Looks at all tags covering the position of iter in the text view, 
# and if one of them is a link, follow it by showing the page identified 
# by the data attached to it. 
#


sub follow_if_link 
{

  my $self = shift;
  my ($text_view, $iter) = @_; 
 
      my $tag = $iter->get_tags; 
      my $file = $tag->{file}; 
 
     if($file) 
     { 
      $self->do_file_search($file); 
      } 
} 



    
1;


__DATA__
=NASDAQ=AAPL
=CUSTOM=AAPL GOOG C BAC WFC WM F
=VIENNA=POS.VI AEM.VI AFND.VI AGR.VI AMAG.VI ANDR.VI ATEC.VI ATFS.VI ATH.VI ATRS.VI ATXS.VI BENE.VI BFC.VI BHD.VI BIND.VI BPTY.VI BWT.VI CAI.VI CERX.VI CNTY.VI CWI.VI CTES.VI DOC.VI EAGB.VI EBAI.VI ECO.VI FKA.VI HEAD.VI HED.VI CHS.VI HIS.VI HTES.VI HUS.VI IATX.VI IBUA.VI ICLL.VI IIA.VI JWD.VI BKS.VI KRGS.VI KTCG.VI LTH.VI STM.VI MTHO.VI NAVN.VI OBS.VI OTS.VI PAL.VI PARS.VI PEP.VI POST.VI PTES.VI PYT.VI
=LONDON=AAAM.L AADV.L AAEV.L AAIF.L AAIG.L AAIW.L AAPV.L AATG.L ABAA.L ABBY.L ABLN.L ABNY.L ABRE.L ABTX.L ACHL.L ACMG.L ACTA.L ACTG.L ACTI.L ADCU.L ADS.L ADID.L ADIS.L ADMF.L ADMS.L AERL.L AFCR.L AFHC.L AFHI.L AFMF.L AFRB.L AGCG.L AGIT.L AGIZ.L AGLD.L AGOE.L AGOL.L AGOU.L AGRE.L AGRG.L AGRI.L AGRP.L AGTA.L AIEA.L AIGA.L AIGC.L AIGE.L AIGG.L AIGI.L AIGL.L AIGO.L AIGP.L AIGS.L AIGX.L AIMI.L AISI.L ALAI.L ALAS.L ALBA.L ALLG.L ALME.L ALPH.L ALTE.L ALUM.L AMBR.L AMEC.L AMEI.L AMER.L ANCR.L ANGM.L ANNA.L ANTO.L ANTP.L ANWS.L APEF.L APNO.L ARBB.L ARCH.L ARCL.L ARDN.L AREO.L ARGO.L ARTA.L ASBE.L ASDX.L ASHM.L ASPL.L ASTO.L ASTR.L ATPT.L ATSS.L ATST.L ATUK.L AUCO.L AUCP.L AUGB.L AUMP.L AURR.L AU.L AVAP.L AVC.L AVCT.L AVIA.L AVON.L AZEM.L BABE.L BABS.L BABU.L BARC.L BARE.L BARS.L BARU.L BASR.L BATS.L BICB.L BCAP.L BDEV.L BEST.L BGBL.L BGFD.L BGHL.L BGHS.L BGIT.L BHCG.L BHCU.L BHGE.L BHGG.L BHGU.L BHME.L BHMG.L BHMU.L BHUE.L BIEM.L BILL.L BILN.L BIOG.L BISI.L BKIC.L BKIR.L BKSA.L BLCK.L BLEY.L BLND.L BLNX.L BLVN.L BMTO.L BNKR.L BNZL.L BODI.L BOOM.L BPFA.L BPFC.L BPFE.L BPFG.L BPFI.L BPFK.L BPFM.L BPFO.L BPFQ.L BPFS.L BPFU.L BPTY.L BRAM.L BRBY.L BRCI.L BRDX.L BREE.L BRFI.L BRGE.L BRGS.L BRIC.L BRLA.L BRLB.L BRNE.L BRNS.L BRSC.L BRSN.L BRST.L BRWM.L BSET.L BSLA.L BSRT.L BSRW.L BSST.L BTEA.L BTEM.L BULL.L BVIC.L BWNG.L BWRA.L BWSA.L BWYA.L BYOT.L CAEL.L CAMB.L CAML.L CAPC.L CAPD.L CAPE.L CARB.L CARE.L CARP.L CASA.L CATF.L CATL.L CTA.L CAZA.L CBIE.L CBIU.L CBRA.L CCAP.L CCPA.L CCPC.L CCSI.L CCVU.L CDFF.L CEAF.L CEBA.L CEBB.L CEMA.L CEME.L CEML.L CEPS.L CEUL.L CEUM.L CFYN.L CGI.L CGNR.L CGOP.L CHAR.L CHGB.L CHNS.L CHRT.L CHTR.L CHWI.L CICR.L CIFU.L CIMB.L CIND.L CINE.L CJPL.L CJPS.L CKSN.L CLDN.L CLEA.L CLIG.L CLLN.L CLON.L CLST.L CLTV.L CMCE.L CMCL.L CMCP.L CMIP.L CMXC.L CNDX.L CNKS.L CNKY.L CNMI.L COAL.L COCG.L COCO.L COCU.L COFF.L COLT.L COMF.L COMS.L CONE.L CONG.L CONU.L COPA.L CORN.L CORO.L COST.L COTN.L COUK.L CPBA.L CPBB.L CPBC.L CPEH.L CPUB.L CPXJ.L CQSU.L CRAW.L CRDA.L CRDG.L CRHL.L CRND.L CRNE.L CRNU.L CRPR.L CRUD.L CRWN.L CRP.L CSAE.L CSAU.L CSB.L CSBR.L CSCA.L CSCG.L CSCL.L CSEM.L CSEO.L CSFG.L CSIN.L CSJP.L CSKR.L CSLT.L CSPX.L CSRT.L CSRU.L CSTW.L CSUK.L CSUS.L CSUZ.L CSWD.L CSZA.L CUKS.L CUKX.L CUSS.L CVA.L CVBP.L CVSG.L CYAN.L DABE.L DABU.L DBAY.L DCLE.L DCLU.L DEMG.L DESC.L DHIR.L DIAM.L DIGI.L DISL.L DIVA.L DJAN.L DJMC.L DJSC.L DJUB.L DLAR.L DMGO.L DMGT.L DNDL.L DNDS.L DNLM.L DODS.L DOTD.L DPLM.L DREF.L DUPD.L DVWA.L DWHA.L DWHT.L DWSN.L DXNS.L EAGA.L EBMB.L EBMC.L ECAP.L ECAW.L ECDC.L ECPC.L ECWL.L ECWO.L ECWS.L ECWZ.L EDIN.L EEMB.L EFMC.L EGU.L EIIB.L ELCO.L ELLA.L ELTA.L ELTC.L ELTZ.L EMED.L EMIS.L ENEF.L ENEG.L ENGI.L ENIZ.L ENRC.L ENRT.L EPIA.L EQPC.L EQPI.L EQPZ.L EQQQ.L EROS.L ESG.L ESSE.L ESSR.L ESTS.L EVOL.L EXEF.L EXPN.L EXXI.L FAGR.L FAIG.L FAME.L FAMT.L FAPX.L FASS.L FBDU.L FCAM.L FCAP.L FCCN.L FCPT.L FCRM.L FCRU.L FCSS.L FDBK.L FDSA.L FENR.L FIND.L FINW.L FIPP.L FITB.L FJVS.L FLIV.L FLTR.L FLYB.L FML.L FMPG.L FMPI.L FOGL.L FOOD.L FOOG.L FOUR.L FPEO.L FPER.L FPET.L FPEZ.L FRCL.L FRES.L FSTA.L FTAS.L FTE.L FUTR.L FWEB.L FWEN.L FXPO.L GACA.L GACB.L GAH.L GBAU.L GBCA.L GBCH.L GBJP.L GBNO.L GBP.L GBSK.L GBUR.L GBUS.L GDIV.L GDWN.L GEEC.L GEMD.L GETS.L GFRD.L GFTU.L GILI.L GILS.L GKP.L GLIF.L GLOK.L GMNT.L GOAL.L GOLD.L GOLE.L GOLG.L GPOR.L GPRT.L GRAF.L GSDE.L GSDO.L GSDU.L GSL.L GVC.L HAIK.L HALB.L HALO.L HALP.L HAMP.L HANA.L HAWK.L HCAN.L HCFT.L HDIV.L HEAD.L HEAF.L HEAT.L HEGY.L HFEL.L HGPC.L HGTS.L HHPG.L HICL.L HIDR.L HILS.L HLCL.L HLMA.L HLTW.L HMBR.L HMCH.L HMCX.L HMEU.L HMEX.L HMFE.L HMJP.L HMLA.L HMLD.L HMLH.L HMSO.L HMUS.L HMWO.L HMXJ.L HMYD.L HOGF.L HOGS.L HOIL.L HOME.L HON.L HOTS.L HPEQ.L HRCO.L HSBA.L HSBR.L HSLE.L HSPB.L HSPX.L HSTN.L HTIG.L HTRY.L HTWD.L HTWN.L HUKX.L HVPE.L HVTA.L HWDN.L HYDG.L HYNS.L HZAR.L IACC.L IAEM.L IAES.L IAEX.L IAPD.L IASP.L IATS.L IAUS.L IBCI.L IBCX.L IBGL.L IBGM.L IBGS.L IBGX.L IBM.L IBPO.L IBTM.L IBTS.L IBZL.L ICAN.L ICEB.L ICGC.L ICOV.L ICTA.L ICTB.L ICTU.L IDAR.L IDEM.L IDJG.L IDJV.L IDOX.L IDVY.L IEAC.L IEAG.L IEEM.L IEER.L IEGA.L IEGE.L IEGY.L IEMA.L IEMB.L IEMI.L IEMS.L IERE.L IERP.L IERW.L IESE.L IEUA.L IEUR.L IEUT.L IEUX.L IEXF.L IFFF.L IGAS.L IGCC.L IGCW.L IGIL.L IGLO.L IGLS.L IGLT.L IGRE.L IGSU.L IHUK.L IHYG.L IIIP.L IJPA.L IJPN.L IKOR.L IMAC.L IMEA.L IMEU.L IMIB.L IMIC.L IMTK.L INAA.L INCH.L INDE.L INDI.L INFA.L INFO.L INFR.L INNO.L INPP.L INRE.L INRG.L INTQ.L INUG.L INVA.L INVP.L INVR.L INVU.L INXG.L IPEL.L IPNT.L IPOL.L IPRP.L IPRT.L IPRU.L IPRV.L IPRZ.L IPSA.L IPXJ.L IRET.L IREZ.L IRGP.L IRSA.L ISAM.L ISAT.L ISEM.L ISFE.L ISJP.L ISPH.L ISUS.L ISWD.L ISXF.L ISYS.L ITKY.L ITPS.L ITRK.L ITWN.L IUKD.L IUKP.L IUSA.L IUSE.L IUSP.L IVPG.L IVPH.L IVPM.L IVPU.L IWDA.L IWDE.L IWDP.L IWRD.L IWXU.L IXMU.L JAIS.L JDTC.L JDTZ.L JEMI.L JESC.L JETG.L JETI.L JGCW.L JIGC.L JIGI.L JIGU.L JIIS.L JLIF.L JMAT.L JMCS.L JMGS.L JPBS.L JPEC.L JPEI.L JPEL.L JPEZ.L JPGB.L JPIZ.L JPIU.L JPLH.L JPM.L JPSS.L JPWW.L JPZZ.L JRIC.L JSJS.L JSSZ.L JSSU.L JUSC.L JUSH.L JZCN.L JZCP.L KCOM.L KDDG.L KEFI.L KENZ.L KESA.L KGI.L KIBO.L KMGA.L KUBC.L KYGA.L LAGR.L LALL.L LALU.L LAUD.L LBRZ.L LCAD.L LCAN.L LCAU.L LCFE.L LCHF.L LCHN.L LCNE.L LCNY.L LCOA.L LCOC.L LCOG.L LCOP.L LCOR.L LCTO.L LCTU.L LCTY.L LDSG.L LEAF.L LEED.L LEEU.L LEFW.L LEMB.L LEME.L LFAS.L LGAS.L LGBP.L LGEN.L LGRA.L LHEA.L LIME.L LIND.L LJPY.L LKUU.L LLAT.L LLCT.L LLEA.L LLGD.L LLHO.L LLOY.L LLPC.L LLPD.L LLPE.L LLPF.L LLPG.L LLPL.L LLST.L LMUS.L LNEY.L LNFT.L LNGA.L LNIK.L LNOK.L LNRG.L LNZD.L LOGP.L LOIL.L LOND.L LONG.L LONR.L LOOK.L LPET.L LPLA.L LPMT.L LQDE.L LSAF.L LSEK.L LSFT.L LSIC.L LSIL.L LSLI.L LSOB.L LSPU.L LSUG.L LSYO.L LTAM.L LTHM.L LTHP.L LTIM.L LTNG.L LTPX.L LWAT.L LWDB.L LWEA.L LWOR.L LYUK.L LYXF.L LZIC.L MACF.L MAJE.L MARL.L MARS.L MASA.L MATD.L MATW.L MAYG.L MBSP.L MBSR.L MCAU.L MCGN.L MCHL.L MCII.L MCKS.L MCRB.L MCRO.L MDST.L MEDG.L MEDI.L MEDU.L MERC.L MERE.L METP.L MGCR.L MGGT.L MGHC.L MGHI.L MGHP.L MGHU.L MGHZ.L MGNS.L MIDD.L MIGT.L MIRA.L MIRL.L MKLW.L MLIN.L MMPW.L MNDI.L MNGS.L MNKS.L MNZS.L MOGP.L MONI.L MONY.L MOOO.L MORT.L MOSB.L MPLE.L MRCH.L MSEG.L MSET.L MSLH.L MSYS.L MTEC.L MTVW.L MUBL.L MVIB.L MWBB.L MWGT.L MWTE.L MWTS.L MWTU.L MXBS.L MXCS.L MXFS.L MXIS.L MYIB.L NABA.L NANO.L NANW.L NARS.L NASA.L NASU.L NATW.L NAWI.L NBDD.L NBDS.L NBNK.L NBPE.L NBPO.L NBPZ.L NBSP.L NBSR.L NCCL.L NCEA.L NCLE.L NCON.L NCYF.L NETD.L NFDS.L NFTY.L NGAF.L NGAS.L NICL.L NOTP.L NRGW.L NRGY.L NRKP.L NRRP.L NTBR.L NTEA.L NTOG.L NUKE.L NVTA.L NWBD.L NWKI.L NZGB.L OBP.L OCDO.L OILB.L OILE.L OILG.L OILW.L OLWP.L OPAY.L OPPP.L OPTS.L OSEC.L OXIG.L PACL.L PALM.L PANR.L PBTY.L PCFB.L PCGH.L PCGS.L PCTS.L PELE.L PEWZ.L PFZ.L PFLB.L PFLM.L PGOO.L PHAG.L PHAU.L PHCU.L PHNX.L PHPD.L PHPM.L PHPT.L PHRM.L PHRX.L PHSC.L PHSN.L PHTM.L PINN.L PINR.L PLAG.L PLAU.L PLAZ.L PLIS.L PLTM.L PMEA.L PMET.L PMHL.L POBA.L POLR.L POWR.L PPIX.L PPTR.L PRA.L PRDF.L PREG.L PRES.L PROV.L PSBW.L PSES.L PSGA.L PSHO.L PSON.L PSPI.L PSRA.L PSRD.L PSRE.L PSRF.L PSRH.L PSRM.L PSRU.L PSRW.L PSSP.L PSWC.L PTCM.L PTEC.L PTMN.L PUMC.L PURE.L PURI.L PVCS.L QRES.L RBLI.L RBPI.L RBPX.L RBRP.L RBSU.L RCDO.L RCHA.L RDEL.L RDES.L RDSA.L RDSB.L RDXS.L REAL.L RECI.L RECP.L REDT.L RENE.L REOA.L REOP.L REUS.L RHEP.L RICA.L RICI.L RICM.L RIFA.L RIIC.L RIIG.L RIII.L RITL.L RKKI.L RNVO.L RNWH.L RONE.L RQIH.L RSAB.L RSOX.L RTTS.L RTWO.L RUBI.L RUSD.L RUSP.L RUSS.L RUSW.L SAFE.L SAGR.L SALL.L SALU.L SANB.L SAND.L BNC.L SAPO.L SAVG.L SBLM.L SBRY.L SBSA.L SBSB.L SBUL.L SCAD.L SCAM.L SCAP.L SCDP.L SCEL.L SCFE.L SCHE.L SCHF.L SCIN.L SCLP.L SCNY.L SCOC.L SCOP.L SCOR.L SCPA.L SCTO.L SDPS.L SDRC.L SDUS.L SEED.L SEGA.L SEGR.L SEPU.L SEUR.L SGAS.L SGBP.L SGBS.L SGLD.L SGRA.L SGRO.L SHEA.L SHFT.L SHIP.L SHLP.L SHRE.L SHRS.L SIAG.L SIGG.L SIHL.L SIME.L SINR.L SIXH.L SJPY.L SKHG.L SKIP.L SKYW.L SLCT.L SLEA.L SLES.L SLET.L SLHO.L SLNG.L SLSC.L SLST.L SLVG.L SLVR.L SLXX.L SMDR.L SMDS.L SMEA.L SMIN.L SMLD.L SMWH.L SNAK.L SNCL.L SNGA.L SNIK.L SNRG.L SNRP.L SNZP.L SOFF.L SOFT.L SOIL.L SOLG.L SOLO.L SORB.L SOYB.L SOYO.L SPET.L SPFL.L SPGH.L SPLA.L SPMG.L SPMT.L SPOL.L SPPC.L SPXJ.L SPXS.L SRE.L SRES.L SRSP.L SSEK.L SSFT.L SSIL.L SSOB.L SSUG.L SSYO.L STAA.L STAB.L STAC.L STAF.L STCM.L STEE.L STEL.L STHR.L STIM.L STOB.L STTM.L STVG.L SUGA.L SUGE.L SUMM.L SVCA.L SWEA.L SYNC.L SZIC.L TAIH.L TALK.L TALV.L TAST.L TATE.L TCSC.L TCTL.L TDE.L TEIF.L TELW.L THAL.L THRG.L THRS.L TIDE.L TIGT.L TINM.L TLDH.L TLPR.L TMMG.L TMPL.L TNCI.L TNOW.L TNZ.L TOPC.L TOYE.L TPOE.L TPOG.L TPOU.L TRAK.L TRAP.L TRBO.L TRCS.L TREE.L TRMA.L TRMB.L TRMU.L TRYS.L TSCO.L TSTL.L TSTR.L TTNM.L UGAS.L UKCM.L UKRO.L ULVR.L UNIQ.L URGB.L USEB.L USGB.L USHD.L USPI.L USPU.L UTIG.L UTIL.L UTLA.L UTLB.L UTLC.L UTLX.L UVEL.L VGAS.L VICT.L VIXS.L VMED.L VPHA.L VSTX.L VSXG.L VSXY.L VXIM.L VXIS.L VYKE.L WATE.L WATR.L WEAT.L WEIR.L WFCA.L WHEG.L WHTE.L WHTG.L WHTU.L WICH.L WIND.L WINK.L WNER.L WOOD.L WORK.L WSAG.L WSPR.L WTAN.L WWHS.L XASX.L XAUS.L XAXJ.L XBCU.L XBRS.L XBUI.L XBUT.L XCAN.L XCAP.L XCRD.L XCRG.L XDBD.L XDBG.L XDER.L XEDS.L XEMD.L XESC.L XESX.L XEUM.L XFVT.L XGBP.L XGFU.L XGID.L XGLD.L XGLE.L XGLR.L XGRD.L XGSD.L XHFD.L XHFE.L XHFG.L XIGS.L XIMT.L XKSD.L XLBS.L XLDX.L XLES.L XLFS.L XLIS.L XLKS.L XLPE.L XLPS.L XLUS.L XLVS.L XMAS.L XMBR.L XMCX.L XMEA.L XMEM.L XMEU.L XMEX.L XMID.L XMJP.L XMLA.L XMLD.L XMMD.L XMRC.L XMTD.L XMTW.L XMUD.L XMUS.L XMWO.L XNIF.L XPAL.L XPLA.L XPXD.L XPXJ.L XSDR.L XSDS.L XSDX.L XSER.L XSES.L XSFR.L XSGI.L XSHE.L XSHJ.L XSHU.L XSIL.L XSIR.L XSIS.L XSKR.L XSKS.L XSNR.L XSPR.L XSPS.L XSPX.L XSSX.L XUGS.L XUIT.L XUKS.L XUKX.L XURA.L XUSD.L XUTD.L XUTS.L XWED.L XWSE.L XWSF.L XWSH.L XWSI.L XWSM.L XWSN.L XWSS.L XWSU.L XWUT.L XWXU.L XXIC.L XXSC.L YELL.L YNGA.L YNGN.L YAU.L YULC.L ZINC.L ZIOC.L
=FRANKFURT=BV5.F BVU.F BVW.F BVXB.F BVYN.F BEM.F BGW.F BWB.F BWC.F BWI.F BWJ.F BWM.F BWQ.F TWB.F BWV.F BWW.F BXE.F BXI.F BXK.F BXO.F BXP.F BXS.F BXX.F BXZ.F BO5.F BYG.F BYH.F BYN.F BYRA.F BYW.F BYY.F PO0.F BZC.F BZD.F BZK.F BZP.F BZT.F UCM.F UCM1.F BZX.F BZY.F BZZ.F RYV.F DBQA.F CA8A.F CAC1.F CAD.F CE9.F XCA.F CAI.F CAJ.F CAK.F CF2.F MN9.F CM2.F CQ2.F YCZ.F CF3.F CMZ.F CAN.F CK1.F CNN1.F CAO.F CAP.F PI6.F CGM.F CAR.F DCN.F CAS.F CAT1.F PLF.F CAU.F CAZ.F CBA.F CWW.F CBE.F CMX.F CBGA.F CBGB.F CS3.F CBHC.F BDZ.F CBK.F XBX.F CBQ.F OLD.F CLB.F CBS.F CU6.F CBT.F CVP.F CBV.F CBW.F CBX.F CCB.F CE3.F CUD.F CEF.F CCI.F UFG.F CVC1.F CMS.F CTD.F CCG.F CCR.F XXY.F CCUN.F CCZA.F COM.F CWH.F CDKM.F CDLN.F CDMA.F CEA.F CIA.F CEBA.F CEBB.F CEBC.F CEBD.F CEBE.F CEBF.F CEBG.F CEBH.F CEBI.F CEBJ.F CEBK.F CEBL.F CEBM.F CEBN.F CEBP.F CEBQ.F CEBR.F CE1.F CEDA.F CEM.F DI1.F CEE.F CGS.F EG9.F CEK.F CENB.F EY3.F CEPN.F ZEP.F CRE.F CU2.F CME.F CEU.F PVJA.F CEV.F CEVJ.F CEXA.F CEXB.F CEZ.F FFC.F CFG.F CFNB.F CFSL.F CFI.F CGEA.F CW9.F CGE.F CG3.F GU8.F CGZ.F CGOA.F CGYK.F YC8.F UC1.F CHIA.F CPW.F CTMA.F NY6.F CWF.F CT4.F CHUA.F XCIA.F CHWD.F CIAH.F CRLN.F CIDA.F CIJN.F CZ7.F CIM.F CIOC.F CPF.F CIR.F CIT.F PXS.F CKDQ.F CKNA.F CQO.F CKZA.F CLDN.F CH6.F CLP.F CLQN.F CLRN.F CA4.F EDT.F CLUG.F CD2.F CMAB.F MAIA.F CMBT.F CTP2.F CMD.F QCX.F CMIC.F CLM.F CID.F CMP.F YCM.F CPV.F CRZ.F CSG.F CC6.F CMUA.F CMV.F CIW.F CLI.F CPL.F EC8.F CNNA.F XNP.F CZT.F NVAD.F CNTA.F CI2.F CNWK.F CS4.F COY.F COC.F CH7.F OHE.F COI.F CU3.F CC5.F COK.F RWC.F CUW.F TCC.F CON.F HTD.F CTO.F COV.F COVN.F CKP.F CPOF.F NVAV.F XEP.F PLZ.F CPQA.F CPRN.F CO6.F PS1.F TBN.F BCR.F OMQ.F CP7.F CWR.F CQDN.F CQIN.F CQJ.F CQMA.F CQR.F CQSB.F CQWA.F CRA1.F CR2.F CRDC.F CRI.F CR1.F CTL.F CR6.F CRG.F CUS.F GGN.F CIP.F XTY.F CC1.F CRU.F CVM.F CRX.F CO1.F CIS.F XCC.F CSX.F CSN.F CSH.F CZ6.F AACA.F AWK.F CS5.F CSUA.F CSS.F COZ.F CTX.F CTYA.F CMY.F HCA.F CVXA.F WA3.F UC4.F CWZN.F KK3.F YTS.F CX5.F CYZA.F CYZB.F CTZ.F QNT1.F DTEA.F DTYN.F DU5.F DUI.F DUV.F DV6.F DVU.F DG1.F DWWE.F DXSA.F DXSB.F DXSC.F DXSD.F DXSE.F DXSF.F DXSG.F DXSH.F DXSI.F DXSJ.F DXSK.F DXSL.F DXSM.F DXSN.F DXSP.F DXSQ.F DXSR.F DXSS.F DXST.F DXSU.F DXSV.F DXSW.F DXSZ.F DXZA.F ESL.F EB5.F ESVN.F ESY.F EUX.F EUZ.F EVTA.F EVT.F EXSA.F EXSB.F EXSC.F EXSD.F EXSE.F EXSG.F EXSH.F EXSI.F EXSJ.F EXM.F EXVM.F EXXT.F EXXU.F EXXV.F EXXW.F EXXX.F EXXY.F FTZ.F FNW.F FXT.F FXXN.F GT2.F GTU.F CFV.F GXSB.F GZWM.F HL5.F HUUA.F HUWA.F HUWH.F HUY.F HUZ.F HWS.F HXXA.F HYVN.F HYW.F IS5.F IOE.F IPT1.F ISZA.F ITTA.F NYVN.F IW3.F IUSA.F IUSB.F IUSC.F IUSD.F IUSE.F IUSF.F IUSK.F IUSL.F IUSM.F IUSP.F IUST.F IUSU.F IVSA.F IVSB.F IVU.F IWUB.F IXU.F IXX.F JTT.F JTVF.F JUVE.F JUWB.F JYS1.F KSW.F KS1A.F KWS.F KYSA.F LDS.F LSX.F LTVA.F LUXA.F LUX.F LS3.F LXS.F LYSX.F LYYA.F LYYB.F LYYC.F LYYE.F LYYG.F LYYH.F LYYI.F LYYK.F LYYL.F LYYM.F LYYN.F LYYP.F LYYQ.F LYYR.F LYYS.F LYYT.F LYYU.F LYYV.F LYYW.F LYYX.F LYYY.F LYYZ.F LZVB.F BW1.F MT7.F MT1.F ALG.F MUS.F MUT.F MUVB.F MVX.F MZX.F MZXJ.F NST.F NPS.F NSU.F NHG.F NU2.F NOTA.F NVW1.F NXWA.F NXWB.F NWU.F NWX.F NXS.F NXZ.F NXU.F AXX.F NYVC.F NYVF.F NYVK.F NYVL.F NYVQ.F NYVU.F NZTA.F ONL.F OA4.F OVER.F EP3.F OSZG.F OUTA.F OM3.F OVXA.F PM3.F PSU.F PQE.F PTOF.F PTTG.F NVA3.F PUS.F PUWA.F PUZ.F PV2.F PVT.F PWVN.F PYXA.F PZS.F QUS.F RSTA.F RSI.F RDS.F VIZ.F RUS.F RUXD.F RDV.F RYSB.F RYTB.F RZS.F SSUN.F SR4.F TA9.F SE3.F DM2.F RJR.F STZA.F STZB.F SUVN.F SWTF.F SWU.F SWV.F SWW.F SWWJ.F SYS.F SRH1.F SYT.F SYW.F IXY.F SYZ.F SZU.F SZZ.F TSTA.F TSTD.F TSWN.F TSXK.F TC9.F TKE.F TUUF.F TWSA.F TWM.F USF.F UEX.F UUU.F UZU.F UZZB.F VS4.F VTSN.F VIU.F VWSA.F WSU.F WVYA.F XSVS.F XSWN.F XYUA.F XYXR.F YSVA.F ZTWN.F
=NYSE=C BAC WFC WM F GE PFE S GM JPM RF LVS MS AA USB XOM MGM T EMC KEY HIG VZ HST GNW COF GS AMD XRX MRK HD MO STI X BK GLW FCX HPQ WMT NLY CHK HAL LOW TXN WFT CIT JNJ SCHW PG DIS COP LNC BMY CAT KIM DOW CVX VLO STT AXP SLM BSX ALU CBS UNH MET SLB KO TGT PRU AIG AMR DHI CVS ABT KFT GPS DYN PNC SPG THC PHM AKS TWX SSCC DD IP EP LUV RAD BBY DUK NBR AFL CBG XL ODP AES TXT GGP NE CSX WEN MRO JCI JNPR LEA PEP LSI WAG PFG NOV IBM GCI MEE MDT WU TRV EQR LEN ALL MCD WMB HL MOS APC STP BTU JCP HCP ACI NSM BA NEM DRE COH OXY IGT IPG PGR HON TYC CLF KR CCL AET TJX MON DDR IR TSO TER WFR NUE NWL AEP JWN MAR UTX LLY GT KSS ADI MMC RCL SLE DE HOT EMR UPS DVN UNP MAS CHS ADM BAX KWK HOG SNV RIG NYX HES NSC MBI UNM MFA FHN SWN TMO NYB FIG WYN KBH ACN PCL YUM GME LTD SO MMM AIV SWY WDC WLP CI EK VTR AMB FNF BXP TWC BHI CB CCE CNO TOL CSE SLG AVP SKS RDC RSH CMA MAC CAG TSN KMX ANR HRB CAM ITW RTN JNS HTZ MTG CNX LM HUN UIS CMS VIA-B FIS EXC HMA AMT DNR APA TEX SYY MDR BDN CL MTW A TIE ESV CNP FLR BX STJ FDX MCO EOG ABC MHS NKE GIS SUN SE D ARO MCK AXL HUM AN TIN AAI HPT XEL SFD PXP HCN CMI MA OI JBL DF NRG SVU PDE NI TIF GD RSG FDO DRI XCO EAT MHP AVB EIX CE RHT PEG FE ORI HOV ACE SNH STZ LMT FTO FL TCB POM CVH PXD LRY BWA REG RRC HNZ BZH FST NOC KMB JEF AGN BYD OMC ASH FCS PCG CAH CPB FRX HP NCR NHP PWR ED SYK O ELX HLX ATI BIG ANN CCK QTM GTI PH CLI WHR MF BMR USU WY SAI BEN DLR K JEC ICE PPL ETN MTU DKS WSM CVC LIZ NBL NFX AG LUK CCI DHR SFI CRM ICO ZMH CPT EXM CVA WLT RYN PBI CTL SHO PIR DOV BDX TE ROK WNR TCO PX FRT AAP FTI KSU NNN CYH BEE RYL SGY EL LXK TMK FO BG PPG UPL GXP KBR RHI RJF JNY ALV AIZ LHO ECL HNT SHW PGN IM ARE MWV AF CEG HRS OMX PL HIW LEG USG CMC MUR NU CS RL COG BRE GES CLX JOE CBE MHK TSS APD VMC ZQK XEC OHI DSX VSH VC NM NLC LXP SRE CDE LPX ETR PSS SPF EV AEE WPI OLN TAP VLY RDN VAR EFX AVT ADS AGO FCE-A ITT BJ SEE GR MMR VG AXS APH FAF TRN PCP STR OCR OFC CBI CNW IRM HCC OC WMS URS PKI WLL PQ RAI CBB HAR WRE R BC FII ACC ATW JAH AOB KNX RWT FLS COL IO BID CXW HBI BGC KRC KMI VFC VIV JLL RGC HSY PNX WAT GMXR MWA LH NCS DOX PNK SIX TSL ANH SPN RS HR OSK VRX ESI PVH SCI BAC-PE HLS EMN ESS BLL DGX KEM TPX HSP HXL ARW FR PKD ELY PLL URI SMG PAY WSH OEH GPC FMC CYN AJG BRO HOC OSG WBS PPS TEN BKE EQT DTE MW CRL PKG AVY BLC PNW NAV DAR WL WOR SWC AZO BCR NYT TDW CSC RT BKS AFG SJM WEC TRW SAH CLP EPR WTI SRZ GWW SWK FOE CRI AMG MPG TK BYI CFR MNI EPD CRK MKC HME SPR LLL FBC TTI GFIG MRX MTH DVA GPN MR SKT PEI SM UHS ZLC PVA WR FBR MTZ MAN CUZ GMT MDU SCG BLK BMS SPW BRY ENR DPL DLB LYV RPM MDC CTB SUG WTR IRC AHT CVG KMP SBH TKR CPX TLB CCC OIS AHL FLO ARG BGP OII GVA PRE KMT GDP TEG BXS HW FNB EME DDS PBY TUP CPO MPW RNR ETP UA MAA RGA ZZ NDN ALK FDS TAM UNT AME HLF FCH SNA CVD ACV POR SI NAT HE PNR APL BBG BOH UGI VAL CYT SFY RAH LNT BKD EPL WCC OKE LZ PNM IRF CMO BGG RMD CMP ALB ITG SWFT PTP ROP DVR RE ENH WCG MIC GGG KCI FBP CRR DRU CQB DHT ACL CNA BEC EBS TRH SVN MDP WCN LTM CPE AB HSC AGP CRS THG ENS CMG CAB OGE IFF BZ WAB CCO GMR CHD ATU ORB DPZ INT COO GRA FCN ONB MLM THI GKK NST SFL LII STE JTX EQY TNB NRF CNL DST WG GS-PD SFG LZB TTC IEX CBT TXI GPI MRH EXP SON SCS EGY ALY EDU DNB RTI NFP AYI CDR EGN MSM PFS KV-A PHH KND FDP FCF ATK DTG HRL LEE DRQ RBC BWS NWY TDG FBN ETE RAS GDI TWI AWH THO ELS NR ATO KEX CSL VCI ANW DFG SFE B ABG GAS PLT TX MWE CPA PII PAA CNH DBD EW AXE MTD WWW HOS GGC IT BCO WXS BDC UTR AYR EVC RKT HS AKR BHE CVO TBL SKX PNY AM AVA GEO NFG WNC ETH OCN FMD OMG DLX SSD SXT CHH DY WGL OFG NJR TFX CSH KKD SF VVC HT EIG POL NCI BKH KNL GWR RGS OMI PRX TNS AEL SRX REV END UNS VQ CLC BAS GET KDN WSO IN CEC MHO NUS MTN MFG FUL GCO AEA DCI TDS CNC GPK WTW BRS NTG CR AGM AWI EPB RGR KFY LNN AIT CPF GRT MCY IDA RDK AHD EXBD GEF NCT KMR HNI ESL CSA BRC IHS NGLS AIR GBE EGP ALEX SWX TRI CBU EE AER TNP ARB NNI ATR SFN GLT PGI UVV SSI HYC SHS CBR PBH TYL HMN ABR CNS SNX HAE RES AOS VMI FIX GHL ALE CW LF GY GOV MMP TDY WTS AIN SSP ORA FSS UIL IVC CLH ABM MGI PKY HHS EEP AHL-PA SSS BWP BLT AIQ GFF DK CLB WGO DAC WPP OMN MIG SWS CODI NRGY VGR BKI NPO ESE MOD CBK UFI MED PAC KOP PRA STC MLI AVX WLK CHC HGR SJI SUP AFT LSE SEH IBI DEP HNR FPO BPL C-PW LXU KBW WST NEU OKS PJC IMN SMA MOH HZO CKH ROL CBZ CKP EDE KEY-PE AHS CHE ESC GB NLS UTI PVR MOV CRY MSA LAD MSO MYE FGP NTE CUB RVI C-PV ROG DKT CGV C-PZ WWE LTC AZZ NX LG JW-A CEL UXG RHB CIR DW TGX NP MOG-A MTX BMI TRK NOA SUI MMS NWN HEI CTS VVI SRI OB NGS TGI OXM ZB-PA BLX DRL RPT JRN ETM USM PRS FVE CWT CGX BAC-PV RSO CBM AWR ACO RLI CMN TG EMS GBX MEG ARJ C-PS DPM SGU HVT FFG OME CAS AEC FUN EDR BBW MCS SXL GTY AVD TVL CIA SUR AEH BBX SWM BMA BTH EVR CDI NRP TNC CAE TR MFW SYX NHI AMN NCC-PA OLP TAL IND KWR MSZ EBF ENZ ALC UNF INZ CYD MSJ GEL SR DDE BIO PKE SPH DCO MER-PF PPD NVR TOO SAM GRB BFS SGK BRK-A MPR MWR KAI HEP STL SFUN SJW CSU LDL CV WMK BAC-PW APU ISG C-PR KCP AP WNA-P CHG MWG JPM-PJ PRM BAC-PX SMP FBF-PM PTI SKY MRT GBL TNH CSV UTL MKL SXI USNA MDS DEL MER-PD OCR-PB BAC-PU FAC ISP MAG LUB DUA NC JPM-PK WTM LDR CNU EEQ CCU BXG NTZ DVD ADC NL SCL DX SRT ISH WPC LVB KSK VHI WPK BXC WPO GS-PC MX TRC MWO ZB-PB JWF NPK CRD-A GPX WNS CPY MLP MER-PE FPC-PA HFC-PB TCAP ASI HBA-PH KEY-PA CPK KRB-PD MPX MSI PHX TVC CTZ-PA MLR PAM SBR ALG WNI PFX JPM-PX FC STN WHG PNU AXR HF GWF KRB-PE NYB-PU USB-PE TVE UBS-PD BK-PF ODC SCX BRT GYB FBF-PN BK-PE XKN RE-PB ALX DDT TRR SLM-PB TCO-PH TPL BGE-PB ARH-PA KEY-PB TUC IHC FLT ALP-PP MPV CFI HYK AAR GPE-PX KRO PJT ABW-PA HBC-P SFI-PI XKK HYL NTL SPA KNO PFG-PB KVR HCN-PF DTE-PA BF-A PL-PB KTV PIJ CPP XKE PL-PA MJH JZC PL-PS DKP TOD KTN CBL-PD NGT PIS PJL NCT-PB TZK XFP ENV KTP PFK VLY-PA PYC KCC HJL PYG CWZ PYS KNR HJJ HZD HJN PJS BXS-PA PYK GNI XFD JZH PJZ XFH PKH KSU-P PYY PIY HZK PKM MJT JBJ KVW MKS GYA JBR PYV HYM IPL-PC HJG HYH MJV DKC KSA ARL KTX RLH-PA PYT GJR PKK PFH PJR GJE KCW MJY PZB HJT ALP-PO DHM HE-PU PKJ JBO PYA GJN GJH CVB TZF FBP-PC PJA GYC PMB-P PYJ GJS JBK HUB-A FBS-PA STL-PA GJD KTH XFR APO DKF PYL XKO GJV MP-PD KRJ GJT HJR HJO GJO GJI GJJ HYY GJP PE-PA GJK HL-PB CMS-PA VEL-PE NMK-PC ED-PC PE-PD NMK-PB XEL-PB PSA-PM PBT PSA-PH CHI PSA-PG CMK FCY JHI NQJ BHK DHG NPV BHD GIM BAC-PB PCM NUC GS-PB BAC-PY OIB DUC FCT NCV HGT NXN GPE-PA WIA DCS DO MXE AHT-PA AWF BTF RVT MRF MKV RCS VNO-PF BAF AT IKR MNP AKP NUV DDF NQI BUD BDJ NQC BDT SJT IIC NUM APF BPK ASG AXS-PA MTR EOS KEF WEA CXE MPJ NPM IKL NPY DOM USB-PJ PCQ JOF MPG-PA KHI MMU IQC SOR MET-PA MQT BNA COY IQI ALQ NNJ DPD AIV-PU BPP FPT HSM MQY NXR NXY-PB KRG ALZ CGO DCT ERF PMX SHO-PA JEQ DCA PFN EGF CRT SGZ NXC NPP NMI VMO VPV PML RFI FMN MZF PMI MGU HPS PMF UBP-PC TFC TSI ARY DSM BME PFO MFL ESD MSF VLT JFC GSF HYV PSA-PE PSB ISM BSD NFJ JGG KED HYB KST BLH IIM BFK GFW PLD MYJ PYN BYM PSY JFR SCD PHD JSN JDD CLD MYF GAM CIF BSP BFZ MFD GAB CHK-PD IMT FT DRE-PN MTS EMQ MAV KT LXP-PB BJZ MUE MSP CSQ DGF MUJ GUT GMA BGT JGV NRC FRA BEE-PB FRB IIF MCI MVC EFR MXE-P MIY GCF HIS MUA EVN ICB EQS HIH IMF BGR GDV-PD VIM LSE-PA NRT PIA MCR ICS LNC-PG NPF JPG TRU JHS ETV ANH-PA EMF UZV NCO JPM-PS PPC JPM-PY NPC LHO-PG DHF PMM AMB-PO DEI KAR UBP JPM-PP GGT ABA FR-PJ PHT UBA JHP MCN ARC FHY GRR CWF NMY NIF AGL BPT NMA RMT RIT DMD HYF MVO ASP PPR RAS-PB EVG GFY EOI CFX NRF-PA ETG MUI JPS F-PA GUL MSY MUC PPT JLA EFT MFV HYI MNE TYN ASA MSB AAV KYN STD-PI ETW C-PU BBK USA VKQ BKT NPT MFM KF NPX BLW ETB MYM NNN-PC TKF MFT TLI FDI MGF BCF CSP BCS-P PZC NAN PLS LXP-PC NQN OSM HTB GEP BOE IFN LDF IGR AEV HCF BQH TYG PHK IMS NMO ZF APB VNO-PH MPA HQH IRR CT PMO ARK NMT NQU AGD MCA IRL MEN WRI CGI VNO-PG NXQ NNF RBS-PP VOQ NNC AIV-PY PNF NAD CHN GEA PNI NQP AIV-PV IQT BNJ VNO BDV HYT CEE GED MET-PB SNF AIV-PT AFB RBS-PR COR TTO TTF HTN MER-PK GFZ COF-PB NMP EEA HBA-PF GEC SGF NXP REG-PE TYY MUS SOV-PB SGL GDL BNY PGH GDF NUN NNP VNO-PA KMM VNV KSM DV CPC IQM VGM DNP CII IKM GF NIO TDI MJI EVT NQM FUR EXR BTA VNO-PE HBA-PG VTJ BTO TRF XAA NAC KYE VVR CUZ-PB MYC DSU ARH-PB AV HIF TW ADX ACP DTF PAI GCV NAZ CCW SEM MYI GUT-PA KEY-PD PSA NTC PFD NTX TY NNY MHR RNE IKJ GCH H ZTR HIX LEO TEI BBF MMT USB-PI TWN SVM RBS-PQ FGI GHI VBF HCN-PD USB-PF MHY PDT AVK CMU BWC ACG HNZ-P RIO NOK TSM PBR DAL M CX ABX GG BBD CIM DFS PBR-A PCS MT POT GGB LCC YGE BP COV IVZ VIP UMC BCS GFI AEO AMX BHP BPO HK MTL AMP SD LDK TEL ABB IBN AUO SU AEM AGU SID HBC ELN AIB L HMY BRK-B CEM STD UN TV KFN GSK CHU TOT DRH AU TS RDS-A SAP CIG CHL RA GNK VMW TDC CF MBT ING TTM AL NVS AZN BBL STM CZZ CLS STO CCJ ASX ACH BR LPL SLT TMX KEG TNE LYG CHT UL SNE COT LFC EXH PHG SKM BVN PRGN CLR MGA DRC HMC PAG SQM ERJ ACM SSW KEP ES LAZ ROC CXO TM IRE TKC FMX AEG RDS-B DEO YZC KB E PTR LGF FTK GFA ABV HXM NTT VR CSR GA LFT ENI TSU CAJ RBA NMR GCA PZE PKX WIT WBC SSL NSR SYT HDB SLH GOL WX CEO IOC ITC BF-B ELP AOI CIB TEF NVO GSI OZM DCM WAL FTE RRR HPY ACW AWC UFS HGG BAP CHA THS GRO WMG WPZ BT UAM LFL CVI CNK LL ABD PSO SBS HRZ DSW NBG SIG TLK OWW DM HNP PUK PPO SAN HTH HUB-B G CBD TEO CUK GTN GLF XRM TPC SCR PMC TI SPP FRZ SMI PHI TGP SEP BAK ALJ NMM NZT SCU NGG ASR WBD NS MEI CRH LUX MFB EOC ICA ABH IDG FMS NPD SKH FRM ADY PT FLY SHG BRP NSH ZEP PZN RBS-PL TGH CFC-PA DXB CPL CRD-B ENL TI-A ZNH DHX TMS FWF MSK KOF IDT TSP MTE MIM PRO DTT HIT FSR OPY RUK DCE ISF BTM ENP QXM UGP NJ VIA BFR NED ATV TMM MXT RBS-PH GMK CAP JMP RBS-PM LEN-B TLP IRS SHI IX CCH HEI-A KUB DEG MAIN GSH IIT CSS HCP-PF DDR-PH RBS-PF RLH FCH-PA NW-PC FCH-PC GLP WBK KYO DDR-PI SFI-PD IEP SLG-PD KIM-PF SFI-PE TGS EDN KV-B WF ALP-PN C-PF CMO-PB AKO-B ATE SFI-PF PRE-PC GRT-PG SLG-PC CEA EQR-PN DRE-PK HBA-PZ RVT-PB GAM-PB IBA BCH RNR-PC HBA-PD CBL-PC SAB PVD KNM PJI BDN-PC GRT-PF BRE-PC ARE-PC DRE-PJ TCO-PG BDN-PD PYB REG-PC TBH VCO HPT-PB CMS-PB GEF-B YPF BRE-PD FJA CBB-PB AO-PA GTN-A CUZ-PA AGM-A SLM-PA BSI HJV PPS-PA XVG BFS-PA GAB-PD AKO-A JZJ HIW-PB FBP-PE JHX BMY-P BCA ED-PA FCE-B JZS RC JZV KRC-PE JZT JBI HJA RMT-PA DD-PB DKQ TCI RFO-PA LTC-PF FBP-PA JZL HVT-A JZK SOR-P PKY-PD GGT-PB C-PH MOG-B GCV-PB FBP-PD JW-B FBP-PB GXP-PA DD-PA XEL-PA STZ-B CMO-PA HCH OFG-PA OFG-PB NAV-PD TY-P TAP-A GMT-P XEL-PG XEL-PE PE-PC SCL-P XEL-PD PBI-P FO-PA PE-PB XEL-PC PSB-PP GXP-PE GIL BAC-PD SPG-PJ GS-PA AES-PC CP NOR PSA-PA PSA-PD AMB-PM PSB-PH EP-PC O-PE PSA-PZ JKS GIB CM GG-WT CNQ EPR-PC HBC-PA PLD-PG REX SOL BMO BIO-B MFC C-PG IAG CTC GDV-PA C-PM RGA-PA RTN-WT PLD-PF TCK AUY MFA-PA ECA TRP O-PD STI-PA UBS FMS-P IHG PSA-PC LHO-PD PSA-PX PSA-PW EOD IAE PCX CPN BCE CPV MS-PA KGC CFC-PB CGA CCZ WRI-PD NXY TBI IVN TAC WRS DRE-PL EXK PRE-PD XCJ OCR-PA FGC KRC-PF PRD DB PDS SFI-PG ENB IPL-PB PSB-PI TU CDR-PA BAC-PL TDS-S DAN AFF BMR-PA BAM AHL-P OFC-PG C-PP OFC-PH AHT-PD HCP-PE GRS ARI RNO EGO AED AEB REG-PD GPM HTY RRTS EXPR EPR-PB RBS-PN VE KFS TLM C-PI FTB-PB NLY-PA TD BNS BHL SJR HEK-WT PAR WRI-PE VNR STD-PB NSP VIT BTE SLF FRO TCL SLW VLY-WT DRE-PO SOA DTK VALE-P STI-PZ DIN HI IPI PNG HTS DPS BAC-PH HCS BBT-PA VRS ABV-C LPS NNA-WT RY FTR GXP-PD RNR-PD DL CNI KCG EXL PWE BPZ GGS BPI EBR-B BML-PH GDL-PA SBX JCI-PZ MTT ABVT ITUB UTA EOT SWI TPZ CEU ZZC CJS CJT IGI IVR DGW WLL-PA JBN CYS PMT CASC AI BIN AMP-PA PSA-PO CXS NEV REN RBS-PG VNOD NVG-PC NNB-PC AON EFM BRFS TCB-WT BZMD CHC-WT IDE NTC-PC NMT-PC NMY-PC NGX-PC ST NPG-PC STNG EQU NEE-PC HPP CWH MSCI VPG
=SP500=MMM ABT ANF ACE ADBE AMD AES AET ACS AFL A APD AKAM AA AYE ATI AGN AW ALL ALTR MO AMZN ABK AEE ACAS AEP AXP AIG ASD AMT AMP ABC AMGN APC ADI BUD AOC APA AIV APOL AAPL ABI AMAT ADM ASH AIZ T ADSK ADP AN AZO AVB AVY AVP BHI BLL BAC BK BCR BRL BAX BBT BSC BDX BBBY BMS BBY BIG BIIB BJS BDK HRB BMC BA BXP BSX BMY BRCM BF.B BC BNI CHRW CA CPB COF CAH CCL CAT CBG CBS CELG CNP CTX CTL SCHW CHK CVX CB CIEN CI CINF CTAS CC CSCO CIT C CZN CTXS CCU CLX CME CMS COH KO CCE CTSH CL CMCSA CMA CBH CSC CPWR CAG COP CNX ED STZ CEG CVG CBE GLW COST CFC CVH COV CSX CMI CVS DHI DHR DRI DF DE DELL DDR DVN DDS DTV DFS D RRD DOV DOW DJ DTE DD DUK DYN ETFC EMN EK ETN EBAY ECL EIX EP ERTS EDS EQ EMC EMR ESV ETR EOG EFX EQR EL EXC EXPE EXPD ESRX XOM FDO FNM FRE FII FDX FIS FITB FHN FE FISV FLR F FRX FO FPL BEN FCX GCI GPS GD GE GIS GM GGP GPC GNW GENZ GILD GS GR GT GOOG GWW HAL HOG HAR HET HIG HAS HNZ HPC HES HPQ HD HON HSP HST HCBK HUM HBAN IACI ITW RX IR TEG INTC ICE IBM IFF IGT IP IPG INTU ITT JBL JEC JNS JDSU JNJ JCI JNY JPM JNPR KBH K KEY KMB KIM KG KLAC KSS KFT KR LLL LH LM LEG LEH LEN LUK LXK LLY LTD LNC LLTC LIZ LMT LTR LOW LSI MTB M MTW MRO MAR MMC MI MAS MAT MBI MKC MCD MHP MCK MWV MHS MDT WFR MRK MDP MER MET MTG MCHP MU MSFT MIL MOLX TAP MON MNST MCO MS MOT MUR MYL NBR NCC NOV NSM NTAP NYT NWL NEM NWS.A GAS NKE NI NE NBL JWN NSC NTRS NOC NOVL NVLS NUE NVDA NYX OXY ODP OMX OMC ORCL PCAR PTV PLL PH PDCO PAYX BTU JCP POM PBG PEP PKI PFE PCG PNW PBI PCL PNC RL PPG PPL PX PCP PFG PG PGN PGR PLD PRU PEG PSA PHM QLGC QCOM DGX STR Q RSH RTN RF RAI RHI ROK COL ROH RDC R SAF SWY SNDK SLE SGP SLB SSP SEE SHLD SRE SHW SIAL SPG SLM SII SNA SO LUV SOV SE S STJ SWK SPLS SBUX HOT STT SYK JAVAD SUN STI SVU SYMC SNV SYY TROW TGT TE TLAB TIN THC TDC TER TEX TSO TXN TXT HSY TRV TMO TIF TWX TIE TJX TMK RIG TRB TEL TYC TSN USB UNP UIS UNH UPS X UTX UNM UST VFC VLO VAR VRSN VZ VIA.B VNO VMC WB WMT WAG DIS WM WMI WAT WPI WFT WLP WFC WEN WU WY WHR WFMI WMB WIN WWY WYE WYN XEL XRX XLNX XL XTO YHOO YUM ZMH ZION
=AMEX=HEB ANX BQI KOG GSX GMO IMH PTN APP GST MEA LNG WYY SUF PDC GGR KAD MMG RAE BVX GHM IGC CVM APT AIS HH LBY LTS RWC MCZ MCF CPD KBX NEP ROX MDF BKR HRT ITI GRC TA INO MGN PRK KAZ UQM ENA AIM VSR BLD NTN HBP LB EPM GVP IPT TMP BTC WLB CMT SNT NHC EAR DGSE LOV OFI IIG GPR CTO UWN JOB UMH BTN IDN AMS STS CCF API MXC BDR LCI BRN IVD DPW ATC SSY PCC CVU WGA FRS CRC CAW FSI HLM-P PNS PDO SIF RVP ABL EML AE MSN IG WSC ACY AXK UUU WEX BHB MSL RPI VII ADK DLA BHO UPG AFP SLI BTC-U DIT ACU SSE AWX ESA TSH GBR INS ICH SGA CRV NLP GIW DXR GLA TOF CIX LGL ESP HWG SVT PW SEB BIR-PA BDL SAL CVR PCG-PD IOT BRD CKX PCG-PE AQQ FWV NEN RVR PET-PA PET-PD PPW-P HMG PET-PB NGB EVO CIL EIV NVG FCO NVY BWL-A CIK DHY EIM CH ENX NHS NOM NZH NEA RNY NNO GGN ERC NNB BPS EGX GLQ NXI DMF BLJ BFY GLO MAB CGL-A VKL GLV VKI NKO NRO MMV NGO BLE MVF EVP RIF MXN EMJ FEN IGC-U PHF NXM MGT NMB PDL-B NGX JRS EVY CCA NXK EVM CEF GSS MZA NMZ JFP NBH BHV NKL GTU NKR UTG NYH ISL NZF PLM MHE FTF NXZ VMV CET NZW NXJ NXE CGC NZR SDO-PB VCF CRF NVJ HDY NZX BZM CEV RFA VMM MXA EMI NRB TGC NFZ CLM GV RNJ RAP EIO GLU TF NPG NII NBO EVJ NBJ NG ULU KRY RTK TGB PAL TRE UEC ANV CFW YMI VGZ BTI SA CGR GRZ VTG UVE PKT NAK PIP SIM ANO HQS CQP PLX CUR OESX KUN NBS FPP AEN ZBB GSB TCX TBV NBY TIS ISR FRD HKN FLL DMC WTT XFN AGX SCE-PC MBR PCG-PA TIK IHT AIP PCG-PC SDO-PC SCE-PE FFI SGB SCE-PD AA-P PCG-PB WLB-P PCG-PH PET-PC CUO WIS-P CNR RBY ZVV XPL NOG MDM EGI PCG-PG BTC-WT PCG-PI AAU ADK-WT RIC NXG SHZ WSO-B ESA-WT BAA SDO-PA FSP HNW IGC-WT NGD AZK ESA-U EMAN URZ CFP MGH CDY MFN CRMD IMO SCE-PB BNX XRA NSU AZC BKJ EVK HNB LZR EGAS INUV CONM IEC CMFO SGS-U NZX-PC SOQ
__END__


=head1 NAME

Finance::Qunat::Home - Generic envirorment for Qunatitative Analysis in finance

=head1 SYNOPSIS


=head1 DESCRIPTION

Basic structure to start qunatitative reasearch in finance

providing 
    
   historycle directory structure
   Fresh symbols
   More symbols
   raid of Institutional Brokers Estimate System - for full strong buy Analysis
   Time-series envirorment
   R quantstrat plotting sandbox
   R back-test sandbox

   enjoy
    


=head2 EXPORT

None by default.

=head2 More

           use strict;
           use warnings;
           use Data::Dumper;
           use threads;
           use Thread::Queue;

           my $q = Thread::Queue->new();    # A new empty queue

           # Worker thread
           my $thr = threads->create(sub {
                                       while (my $item = $q->dequeue()) {
                                           # Do work on $item
                                       }
                                    })->detach();

=head1 SEE ALSO

Finance::Google::Sector::Mean
Finance::NASDAQ::Markets

=head1 AUTHOR

Hagen Geissler

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Hagen Geissler

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.12.4 or,
at your option, any later version of Perl 5 you may have available.


=cut