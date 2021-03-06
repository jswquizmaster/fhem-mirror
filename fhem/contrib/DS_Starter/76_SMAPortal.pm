#########################################################################################################################
# $Id: 76_SMAPortal.pm 00000 2019-03-14 20:21:11Z DS_Starter $
#########################################################################################################################
#       76_SMAPortal.pm
#
#       (c) 2019 by Heiko Maaz
#       e-mail: Heiko dot Maaz at t-online dot de
#
#       This module can be used to get data from SMA Portal https://www.sunnyportal.com/Templates/Start.aspx .
# 
#       This script is part of fhem.
#
#       Fhem is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 2 of the License, or
#       (at your option) any later version.
#
#       Fhem is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#       This module is based on the modules (Thanks to all!):
#       98_SHM.pm                  from author Brun von der Gönne <brun at goenne dot de>
#       98_SHMForecastRelative.pm  from author BerndArnold
#       
#       FHEM Forum: http://forum.fhem.de/index.php/topic,27667.0.html 
#
#########################################################################################################################
#
# Definition: define <name> SMAPortal
#
#########################################################################################################################

package main;
use strict;
use warnings;
eval "use FHEM::Meta;1";

###############################################################
#                  SMAPortal Initialize
# Da ich mit package arbeite müssen für die jeweiligen hashFn 
# Funktionen der Funktionsname und davor mit :: getrennt der 
# eigentliche package Name des Modules
###############################################################
sub SMAPortal_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}         = "FHEM::SMAPortal::Define";
  $hash->{UndefFn}       = "FHEM::SMAPortal::Undefine";
  $hash->{DeleteFn}      = "FHEM::SMAPortal::Delete"; 
  $hash->{AttrFn}        = "FHEM::SMAPortal::Attr";
  $hash->{SetFn}         = "FHEM::SMAPortal::Set";
  $hash->{GetFn}         = "FHEM::SMAPortal::Get";
  $hash->{DbLog_splitFn} = "FHEM::SMAPortal::DbLog_split";
  $hash->{AttrList}      = "cookieLocation ".
                           "cookielifetime ".
                           "detailLevel:1,2,3,4 ".
                           "disable:0,1 ".
                           "getDataRetries:1,2,3,4,5,6,7,8,9,10 ".
                           "interval ".
                           "showPassInLog:1,0 ".
                           "timeout ". 
                           "userAgent ".
                           $readingFnAttributes;

  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };          # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)

return; 
}

###############################################################
#                    Begin Package
###############################################################
package FHEM::SMAPortal;
use strict;
use warnings;
use GPUtils qw(:all);                   # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt
use POSIX;
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1;
use Data::Dumper;
use Blocking;
use Time::HiRes qw(gettimeofday);
use Time::Local;
use LWP::UserAgent;
use HTTP::Cookies;
use JSON qw(decode_json);
use MIME::Base64;
use Encode;

# Run before module compilation
BEGIN {
  # Import from main::
  GP_Import( 
      qw(
          attr
          AttrVal
          addToDevAttrList
          addToAttrList
          BlockingCall
          BlockingKill
          CommandAttr
          CommandDefine
          CommandDeleteAttr
          CommandDeleteReading
          CommandSet
          defs
          delFromDevAttrList
          delFromAttrList
          devspec2array
          deviceEvents
          Debug
          FmtDateTime
          FmtTime
          fhemTimeGm
          getKeyValue
          gettimeofday
          genUUID
          init_done
          InternalTimer
          IsDisabled
          Log
          Log3         
          modules          
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsDelete
          readingsEndUpdate
          ReadingsNum
          ReadingsVal
          RemoveInternalTimer
          setKeyValue
          sortTopicNum
          TimeNow
          Value
        )
  );
}

# Versions History intern
our %vNotesIntern = (
  "1.6.0"  => "29.04.2019  function PortalAsHtml ",
  "1.5.5"  => "22.04.2019  fix readings for BattryOut and BatteryIn ",
  "1.5.4"  => "26.03.2019  delete L1_InfoMessages if no info occur ",
  "1.5.3"  => "26.03.2019  delete L1_ErrorMessages, L1_WarningMessages if no errors or warnings occur ",
  "1.5.2"  => "25.03.2019  prevent module from deactivation in case of unavailable Meta.pm ",
  "1.5.1"  => "24.03.2019  fix \$VAR1 problem Forum: #27667.msg922983.html#msg922983 ",
  "1.5.0"  => "23.03.2019  add consumer data ",
  "1.4.0"  => "22.03.2019  add function extractPlantData, DbLog_split, change L2 Readings ",
  "1.3.0"  => "18.03.2019  change module to use package FHEM::SMAPortal and Meta.pm, new sub setVersionInfo ",
  "1.2.3"  => "12.03.2019  make ready for 98_Installer.pm ", 
  "1.2.2"  => "11.03.2019  new Errormessage analyze added, make ready for Meta.pm ", 
  "1.2.1"  => "10.03.2019  behavior of state changed, commandref revised ", 
  "1.2.0"  => "09.03.2019  integrate weather data, minor fixes ",
  "1.1.0"  => "09.03.2019  make get data more stable, new attribute \"getDataRetries\" ",
  "1.0.0"  => "03.03.2019  initial "
);

###############################################################
#                         SMAPortal Define
###############################################################
sub Define($$) {
  my ($hash, $def) = @_;
  my @a = split(/\s+/, $def);
  
  return "Wrong syntax: use \"define <name> SMAPortal\" " if(int(@a) < 1);

  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);   # Modul Meta.pm nicht vorhanden
  
  # Versionsinformationen setzen
  setVersionInfo($hash);
  
  getcredentials($hash,1);     # Credentials lesen und in RAM laden ($boot=1)
  CallInfo($hash);             # Start Daten Abrufschleife
  delcookiefile($hash);        # Start Schleife regelmäßiges Löschen Cookiefile
 
return undef;
}

###############################################################
#                         SMAPortal Undefine
###############################################################
sub Undefine($$) {
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  BlockingKill($hash->{HELPER}{RUNNING_PID}) if($hash->{HELPER}{RUNNING_PID});

return undef;
}

###############################################################
#                         SMAPortal Delete
###############################################################
sub Delete($$) {
    my ($hash, $arg) = @_;
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
    my $name  = $hash->{NAME};
    
    # gespeicherte Credentials löschen
    setKeyValue($index, undef);
    
return undef;
}

###############################################################
#                          SMAPortal Set
###############################################################
sub Set($@) {
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name    = $a[0];
  my $opt     = $a[1];
  my $prop    = $a[2];
  my $prop1   = $a[3];
  my ($setlist,$success);
        
  return if(IsDisabled($name));
 
  if(!$hash->{CREDENTIALS}) {
      # initiale setlist für neue Devices
      $setlist = "Unknown argument $opt, choose one of ".
	             "credentials "
                 ;  
  } else {
      # erweiterte Setlist wenn Credentials gesetzt
      $setlist = "Unknown argument $opt, choose one of ".
	             "credentials ".
                 "createPortalGraphic:noArg "
                 ;   
  }  

  if ($opt eq "credentials") {
      return "Credentials are incomplete, use username password" if (!$prop || !$prop1);    
      ($success) = setcredentials($hash,$prop,$prop1); 
	  
	  if($success) {
          CallInfo($hash);
		  return "Username and Password saved successfully";
	  } else {
		   return "Error while saving Username / Password - see logfile for details";
	  }
			
  } elsif ($opt eq "createPortalGraphic") {
	  if (!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials username password\"";}
	  my ($htmldev,$ret);
      
      $htmldev = "WL.$name";
      $ret = CommandDefine($hash->{CL},"$htmldev weblink htmlCode {FHEM::SMAPortal::PortalAsHtml (\"$name\")}");
      return $ret if($ret);
      my $c = "This device provides a praphical output of SMA Portal values.\n". 
              "The device needs to set attribute \"detailLevel\" in device \"$name\" to level \"4\"";
      CommandAttr($hash->{CL},"$htmldev comment $c"); 
      $c = "SMA Portal Graphics";
      CommandAttr($hash->{CL},"$htmldev alias $c");
      
	  my $room = AttrVal($name,"room","SMAPortal");
      CommandAttr($hash->{CL},"$htmldev room $room");
      CommandAttr($hash->{CL},"$name detailLevel 4");
	  return "SMA Portal Graphics device \"$htmldev\" created and assigned to room \"$room\".";
  
  } else {
      return "$setlist";
  }  
  
return;
}

###############################################################
#               SMAPortal DbLog_splitFn
###############################################################
sub DbLog_split($$) {
  my ($event, $device) = @_;
  my $devhash = $defs{$device};
  my ($reading, $value, $unit);

  if($event =~ m/L2_PlantPeakPower/) {
      $event   =~ /^L2_PlantPeakPower:\s(.*)\s(.*)/;
      $reading = "L2_PlantPeakPower";
	  $value   = $1;
	  $unit    = $2;
  }   
  if($event =~ m/L1_.*_Temperature/) {
      $event   =~ /^L1_(.*)_Temperature:\s(.*)\s(.*)/;
      $reading = "L1_$1_Temperature";
	  $value   = $2;
	  $unit    = $3;
  } 
  if($event =~ m/summary/) {
      $event   =~ /summary:\s(.*)\s(.*)/;
      $reading = "summary";
	  $value   = $1;
	  $unit    = $2;
  } 
  
return ($reading, $value, $unit);
}

######################################################################################
#                            Username / Paßwort speichern
######################################################################################
sub setcredentials ($@) {
    my ($hash, @credentials) = @_;
    my $name                 = $hash->{NAME};
    my ($success, $credstr, $index, $retcode);
    my (@key,$len,$i);    
    
    $credstr = encode_base64(join(':', @credentials));
    
    # Beginn Scramble-Routine
    @key = qw(1 3 4 5 6 3 2 1 9);
    $len = scalar @key;  
    $i = 0;  
    $credstr = join "",  
            map { $i = ($i + 1) % $len;  
            chr((ord($_) + $key[$i]) % 256) } split //, $credstr; 
    # End Scramble-Routine    
       
    $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
    $retcode = setKeyValue($index, $credstr);
    
    if ($retcode) { 
        Log3($name, 1, "$name - Error while saving the Credentials - $retcode");
        $success = 0;
    } else {
        getcredentials($hash,1);        # Credentials nach Speicherung lesen und in RAM laden ($boot=1)
        $success = 1;
    }

return ($success);
}

######################################################################################
#                             Username / Paßwort abrufen
######################################################################################
sub getcredentials ($$) {
    my ($hash,$boot) = @_;
    my $name         = $hash->{NAME};
    my ($success, $username, $passwd, $index, $retcode, $credstr);
    my (@key,$len,$i);
    
    if ($boot) {
        # mit $boot=1 Credentials von Platte lesen und als scrambled-String in RAM legen
        $index = $hash->{TYPE}."_".$hash->{NAME}."_credentials";
        ($retcode, $credstr) = getKeyValue($index);
    
        if ($retcode) {
            Log3($name, 2, "$name - Unable to read password from file: $retcode");
            $success = 0;
        }  

        if ($credstr) {
            # beim Boot scrambled Credentials in den RAM laden
            $hash->{HELPER}{CREDENTIALS} = $credstr;
    
            # "Credentials" wird als Statusbit ausgewertet. Wenn nicht gesetzt -> Warnmeldung und keine weitere Verarbeitung
            $hash->{CREDENTIALS} = "Set";
            $success = 1;
        }
    } else {
        # boot = 0 -> Credentials aus RAM lesen, decoden und zurückgeben
        $credstr = $hash->{HELPER}{CREDENTIALS};
        
        if($credstr) {
            # Beginn Descramble-Routine
            @key = qw(1 3 4 5 6 3 2 1 9); 
            $len = scalar @key;  
            $i = 0;  
            $credstr = join "",  
            map { $i = ($i + 1) % $len;  
            chr((ord($_) - $key[$i] + 256) % 256) }  
            split //, $credstr;   
            # Ende Descramble-Routine
            
            ($username, $passwd) = split(":",decode_base64($credstr));
            
            my $logpw = AttrVal($name, "showPassInLog", "0") == 1 ? $passwd : "********";
        
            Log3($name, 3, "$name - Credentials read from RAM: $username $logpw");
        
        } else {
            Log3($name, 1, "$name - Credentials not set in RAM !");
        }
    
        $success = (defined($passwd)) ? 1 : 0;
    }

return ($success, $username, $passwd);        
}

###############################################################
#                          SMAPortal Get
###############################################################
sub Get($$) {
 my ($hash, @a) = @_;
 return "\"get X\" needs at least an argument" if ( @a < 2 );
 my $name = shift @a;
 my $opt  = shift @a;
   
 my  $getlist = "Unknown argument $opt, choose one of ".
                "storedCredentials:noArg ".
                "data:noArg ";
                   
 return "module is disabled" if(IsDisabled($name));
  
 if ($opt eq "data") {
     CallInfo($hash);
 
 } elsif ($opt eq "storedCredentials") {
	    if(!$hash->{CREDENTIALS}) {return "Credentials of $name are not set - make sure you've set it with \"set $name credentials &lt;username&gt; &lt;password&gt;\"";}
        # Credentials abrufen
        my ($success, $username, $password) = getcredentials($hash,0);
        unless ($success) {return "Credentials couldn't be retrieved successfully - see logfile"};
        
        return "Stored Credentials to access SMA Portal:\n".
               "========================================\n".
               "Username: $username, Password: $password\n".
               "\n";
                
 } else {
     return "$getlist";
 } 
return undef;
}

###############################################################
#                          SMAPortal Attr
###############################################################
sub Attr($$$$) {
    my ($cmd,$name,$aName,$aVal) = @_;
    my $hash = $defs{$name};
    my ($do,$val);
    
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
    
    if ($aName eq "disable") {
        if($cmd eq "set") {
            $do = ($aVal) ? 1 : 0;
        }
        $do  = 0 if($cmd eq "del");
		$val = ($do == 1 ? "disabled" : "initialized");
        
        if($do) {
            delread($hash);
            delete $hash->{MODE};
            RemoveInternalTimer($hash);            
            delcookiefile($hash,1);            
        } else {
            InternalTimer(gettimeofday()+1.0, "FHEM::SMAPortal::CallInfo", $hash, 0);
            InternalTimer(gettimeofday()+5.0, "FHEM::SMAPortal::delcookiefile", $hash, 0);
        }
	    
        readingsBeginUpdate($hash);
	    readingsBulkUpdate($hash, "state", $val);
	    readingsEndUpdate($hash, 1);
    }
    
    if ($cmd eq "set") {
        if ($aName =~ m/timeout|interval/) {
            unless ($aVal =~ /^\d+$/) {return " The Value for $aName is not valid. Use only figures 0-9 !";}
        }
        if($aName =~ m/interval/) {
            InternalTimer(gettimeofday()+1.0, "FHEM::SMAPortal::CallInfo", $hash, 0);
        }        
    }

return undef;
}

################################################################
##               Hauptschleife BlockingCall
################################################################
sub CallInfo($) {
  my ($hash)   = @_;
  my $name     = $hash->{NAME};
  my $timeout  = AttrVal($name, "timeout", 30);
  my $interval = AttrVal($name, "interval", 300);
  my $new;
  
  RemoveInternalTimer($hash,"FHEM::SMAPortal::CallInfo");
  
  if($init_done == 1) {
      if(!$hash->{CREDENTIALS}) {
          Log3($name, 1, "$name - Credentials not set. Set it with \"set $name credentials <username> <password>\""); 
          readingsSingleUpdate($hash, "state", "Credentials not set", 1);    
          return;          
      }
      
      if(!$interval) {
          $hash->{MODE} = "Manual";
      } else {
          $new = gettimeofday()+$interval; 
          InternalTimer($new, "FHEM::SMAPortal::CallInfo", $hash, 0);
          $hash->{MODE} = "Automatic - next polltime: ".FmtTime($new);
      }

      return if(IsDisabled($name));
      
      if ($hash->{HELPER}{RUNNING_PID}) {
          BlockingKill($hash->{HELPER}{RUNNING_PID});
          delete($hash->{HELPER}{RUNNING_PID});
      } 
      
	  $hash->{HELPER}{RETRIES} = AttrVal($name, "getDataRetries", 3);
      $hash->{HELPER}{RUNNING_PID} = BlockingCall("FHEM::SMAPortal::GetData", $name, "FHEM::SMAPortal::ParseData", $timeout, "FHEM::SMAPortal::ParseAborted", $hash);
      $hash->{HELPER}{RUNNING_PID}{loglevel} = 5 if($hash->{HELPER}{RUNNING_PID});  # Forum #77057
  
  } else {
      InternalTimer(gettimeofday()+5, "FHEM::SMAPortal::CallInfo", $hash, 0);
  }
    
return;  
}

################################################################
##                  Datenabruf SMA-Portal
################################################################
sub GetData($) {
  my ($name) = @_;
  my $hash   = $defs{$name};
  my ($livedata_content);
  my $login_state = 0;
  my ($forecast_content,$weatherdata_content) = ("","");
  my $useragent      = AttrVal($name, "userAgent", "Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.2; Trident/6.0)");
  my $cookieLocation = AttrVal($name, "cookieLocation", "./log/mycookies.txt"); 
   
  Log3 $name, 5, "$name - Start BlockingCall GetData with CookieLocation: $cookieLocation and UserAgent: $useragent";
  
  my $ua = LWP::UserAgent->new;

  # Define user agent type
  $ua->agent("$useragent");
  
  # Cookies
  $ua->cookie_jar(HTTP::Cookies->new( file           => "$cookieLocation",
                                      ignore_discard => 1,
                                      autosave       => 1
                                    )
                 );
  
  # Sunny Home Manager Seite abfragen 
  my $livedata = $ua->get('https://www.sunnyportal.com/homemanager');

  if(($livedata->content =~ m/FeedIn/i) && ($livedata->content !~ m/expired/i)) {
      Log3 $name, 4, "$name - Login to SMA-Portal succesful";
      
      # JSON Live Daten
      $livedata_content = $livedata->content;
      $login_state = 1;
      Log3 $name, 4, "$name - Getting live data now";
      Log3 $name, 5, "$name - Data received:\n".Dumper decode_json($livedata_content);
      
      # JSON Wetterdaten
      Log3 $name, 4, "$name - Getting weather data now";
      my $weatherdata = $ua->get('https://www.sunnyportal.com/Dashboard/Weather');
      $weatherdata_content = $weatherdata->content;
      Log3 $name, 5, "$name - Data received:\n".Dumper decode_json($weatherdata_content);
      
      # JSON Forecast Daten
      my $dl = AttrVal($name, "detailLevel", 1);
      if($dl > 1) {
          Log3 $name, 4, "$name - Getting forecast data now";

          my $forecast_page = $ua->get('https://www.sunnyportal.com/HoMan/Forecast/LoadRecommendationData');
          Log3 $name, 5, "$name - Return Code: ".$forecast_page->code;

          if ($forecast_page->content =~ m/ForecastChartDataPoint/i) {
              $forecast_content = $forecast_page->content;
              Log3 $name, 5, "$name - Forecast Data received:\n".Dumper decode_json($forecast_content);
          }
      }
  
  } else {
      my $usernameField = "ctl00\$ContentPlaceHolder1\$Logincontrol1\$txtUserName";
      my $passwordField = "ctl00\$ContentPlaceHolder1\$Logincontrol1\$txtPassword";
      my $loginField    = "__EVENTTARGET";
      my $loginButton   = "ctl00\$ContentPlaceHolder1\$Logincontrol1\$LoginBtn";
      
      Log3 $name, 3, "$name - not logged in. Try again ...";
      
      # Credentials abrufen
      my ($success, $username, $password) = getcredentials($hash,0);
  
      unless ($success) {
          Log3($name, 1, "$name - Credentials couldn't be retrieved successfully - make sure you've set it with \"set $name credentials <username> <password>\"");   
          $login_state = 0;
      
      } else {    
          my $loginp = $ua->post('https://www.sunnyportal.com/Templates/Start.aspx',[$usernameField => $username, $passwordField => $password, "__EVENTTARGET" => $loginButton]);
        
          Log3 $name, 4, "$name -> ".$loginp->code;
          Log3 $name, 5, "$name -> Login-Page return: ".$loginp->content;
        
          if( $loginp->content =~ /Logincontrol1_ErrorLabel/i ) {
              Log3 $name, 1, "$name - Error: login to SMA-Portal failed";
              $livedata_content = "{\"Login-Status\":\"failed\"}";
          } else {
              Log3 $name, 3, "$name - login to SMA-Portal successful ... ";
              $livedata_content = '{"Login-Status":"successful", "InfoMessages":["login to SMA-Portal successful but get data with next data cycle."]}';
              $login_state = 1;
          }

          my $shmp = $ua->get('https://www.sunnyportal.com/FixedPages/HoManLive.aspx');
          Log3 $name, 5, "$name -> ".$shmp->code;
      }
  }
  
  my ($reread,$retry) = analivedat($hash,$livedata_content);
  
  # Daten müssen als Einzeiler zurückgegeben werden
  $livedata_content    = encode_base64($livedata_content,"");
  $forecast_content    = encode_base64($forecast_content,"") if($forecast_content);
  $weatherdata_content = encode_base64($weatherdata_content,"") if($weatherdata_content);

return "$name|$livedata_content|$forecast_content|$weatherdata_content|$login_state|$reread|$retry";
}

################################################################
##  Verarbeitung empfangene Daten, setzen Readings
################################################################
sub ParseData($) {
  my ($string) = @_;
  my @a = split("\\|",$string);
  my $hash        = $defs{$a[0]};
  my $name        = $hash->{NAME};
  my $ld_response = decode_base64($a[1]);
  my $fd_response = decode_base64($a[2]) if($a[2]);
  my $wd_response = decode_base64($a[3]) if($a[3]);
  my $login_state = $a[4];
  my $reread      = $a[5];
  my $retry       = $a[6];
  
  my $livedata_content    = decode_json($ld_response);
  my $forecast_content    = decode_json($fd_response) if($fd_response);
  my $weatherdata_content = decode_json($wd_response) if($wd_response);
  
  my $state = "ok";
  
  my $timeout = AttrVal($name, "timeout", 30);
  if($reread) {
      # login war erfolgreich, aber Daten müssen jetzt noch gelesen werden
	  delete($hash->{HELPER}{RUNNING_PID});
      readingsSingleUpdate($hash, "L1_Login-Status", "successful", 1);
      $hash->{HELPER}{oldlogintime} = gettimeofday();
	  $hash->{HELPER}{RUNNING_PID} = BlockingCall("FHEM::SMAPortal::GetData", $name, "FHEM::SMAPortal::ParseData", $timeout, "FHEM::SMAPortal::ParseAborted", $hash);
      $hash->{HELPER}{RUNNING_PID}{loglevel} = 5 if($hash->{HELPER}{RUNNING_PID});  # Forum #77057
      return;
  }
  if($retry && $hash->{HELPER}{RETRIES}) {
      # Livedaten konnte nicht gelesen werden, neuer Versuch zeitverzögert
	  delete($hash->{HELPER}{RUNNING_PID});
	  $hash->{HELPER}{RETRIES} -= 1;
      InternalTimer(gettimeofday()+5, "FHEM::SMAPortal::retrygetdata", $hash, 0);
      return;
  }  
  
  my $dl = AttrVal($name, "detailLevel", 1);
  delread($hash, $dl+1);
  
  readingsBeginUpdate($hash);
  
  my ($FeedIn_done,$GridConsumption_done,$PV_done,$AutarkyQuote_done,$SelfConsumption_done) = (0,0,0,0,0);
  my ($SelfConsumptionQuote_done,$SelfSupply_done,$errMsg,$warnMsg,$infoMsg) = (0,0,0,0,0);
  my ($batteryin,$batteryout);
  for my $k (keys %$livedata_content) {
      my $new_val = ""; 
      if (defined $livedata_content->{$k}) {
          if (($livedata_content->{$k} =~ m/ARRAY/i) || ($livedata_content->{$k} =~ m/HASH/i)) {
              Log3 $name, 4, "$name - Livedata content \"$k\": ".($livedata_content->{$k});
              if($livedata_content->{$k} =~ m/ARRAY/i) {
                  my $hd0 = $livedata_content->{$k}[0];
                  if(!defined $hd0) {
                      next;
                  }
                  chomp $hd0;
                  $hd0 =~ s/[;']//g;
                  $hd0 = encode("utf8", $hd0);
                  Log3 $name, 4, "$name - Livedata \"$k\": $hd0";
                  $new_val = $hd0;
              }
		  } else {
              $new_val = $livedata_content->{$k};
          }
        
          if ($new_val && $k !~ /__type/i) {
              Log3 $name, 4, "$name -> $k - $new_val";
              readingsBulkUpdate($hash, "L1_$k", $new_val);
              $FeedIn_done               = 1 if($k =~ /^FeedIn$/);
              $GridConsumption_done      = 1 if($k =~ /^GridConsumption$/);
              $PV_done                   = 1 if($k =~ /^PV$/);
              $AutarkyQuote_done         = 1 if($k =~ /^AutarkyQuote$/);
              $SelfConsumption_done      = 1 if($k =~ /^SelfConsumption$/);
              $SelfConsumptionQuote_done = 1 if($k =~ /^SelfConsumptionQuote$/);
              $SelfSupply_done           = 1 if($k =~ /^SelfSupply$/);
              $errMsg                    = 1 if($k =~ /^ErrorMessages$/);
              $warnMsg                   = 1 if($k =~ /^WarningMessages$/);
              $infoMsg                   = 1 if($k =~ /^InfoMessages$/);
              $batteryin                 = 1 if($k =~ /^BatteryIn$/);
              $batteryout                = 1 if($k =~ /^BatteryOut$/);
          }
      }
  }
  
  readingsBulkUpdate($hash, "L1_FeedIn", 0) if(!$FeedIn_done);
  readingsBulkUpdate($hash, "L1_GridConsumption", 0) if(!$GridConsumption_done);
  readingsBulkUpdate($hash, "L1_PV", 0) if(!$PV_done);
  readingsBulkUpdate($hash, "L1_AutarkyQuote", 0) if(!$AutarkyQuote_done);
  readingsBulkUpdate($hash, "L1_SelfConsumption", 0) if(!$SelfConsumption_done);
  readingsBulkUpdate($hash, "L1_SelfConsumptionQuote", 0) if(!$SelfConsumptionQuote_done);
  readingsBulkUpdate($hash, "L1_SelfSupply", 0) if(!$SelfSupply_done);
  if(defined $batteryin || defined $batteryout) {
      readingsBulkUpdate($hash, "L1_BatteryIn", 0) if(!$batteryin);
      readingsBulkUpdate($hash, "L1_BatteryOut", 0) if(!$batteryout);
  }  
  readingsEndUpdate($hash, 1);
  
  readingsDelete($hash,"L1_ErrorMessages") if(!$errMsg);
  readingsDelete($hash,"L1_WarningMessages") if(!$warnMsg);
  readingsDelete($hash,"L1_InfoMessages") if(!$infoMsg);
  
  if ($forecast_content && $forecast_content !~ m/undefined/i) {
      # Auswertung der Forecast Daten
      extractForecastData($hash,$forecast_content);
      extractPlantData($hash,$forecast_content);
      extractConsumerData($hash,$forecast_content);
  }
  
  if ($weatherdata_content && $weatherdata_content !~ m/undefined/i) {
      # Auswertung Wetterdaten
      extractWeatherData($hash,$weatherdata_content);
  }
  
  my $pv = ReadingsVal($name, "L1_PV", 0);
  my $fi = ReadingsVal($name, "L1_FeedIn", 0);
  my $gc = ReadingsVal($name, "L1_GridConsumption", 0);
  my $sum = $fi-$gc;
  
  if(!$hash->{HELPER}{RETRIES} && !$pv && !$fi && !$gc) {
      # keine Anlagendaten vorhanden
      $state = "Data can't be retrieved from SMA-Portal. Reread at next scheduled cycle.";
      Log3 $name, 2, "$name - $state";
  }
  
  readingsBeginUpdate($hash);
  if($login_state) {
      readingsBulkUpdate($hash, "state", $state);
      readingsBulkUpdate($hash, "summary", "$sum W");
  } 
  readingsEndUpdate($hash, 1);
  
  delete($hash->{HELPER}{RUNNING_PID});
}

################################################################
##                   Timeout  BlockingCall
################################################################
sub ParseAborted($) {
  my ($hash,$cause) = @_;
  my $name = $hash->{NAME};
   
  $cause = $cause?$cause:"Timeout: process terminated";
  Log3 ($name, 1, "$name -> BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} pid:$hash->{HELPER}{RUNNING_PID}{pid} $cause");

  delete($hash->{HELPER}{RUNNING_PID});
}

################################################################
##             regelmäßig Cookie-Datei löschen
################################################################
sub delcookiefile ($;$) {
   my ($hash,$must) = @_;
   my $name         = $hash->{NAME};
   my ($validperiod, $cookieLocation, $oldlogintime, $delfile);
   
   RemoveInternalTimer($hash,"FHEM::SMAPortal::delcookiefile");
   
   # Gültigkeitsdauer Cookie in Sekunden
   $validperiod    = AttrVal($name, "cookielifetime", 3000);    
   $cookieLocation = AttrVal($name, "cookieLocation", "./log/mycookies.txt"); 
   
   if($must) {
       # Cookie Zwangslöschung
       $delfile = unlink($cookieLocation);
   }
   
   $oldlogintime = $hash->{HELPER}{oldlogintime}?$hash->{HELPER}{oldlogintime}:0;
   
   if($init_done == 1) {
       # Abfrage ob gettimeofday() größer ist als gettimeofday()+$validperiod
       if (gettimeofday() > $oldlogintime+$validperiod) {
            $delfile = unlink($cookieLocation);
       }
   } 
           
   if($delfile) {
       Log3 $name, 3, "$name - cookie file deleted: $cookieLocation";  
   } 
   
   return if(IsDisabled($name));
   
   InternalTimer(gettimeofday()+30, "FHEM::SMAPortal::delcookiefile", $hash, 0);

return;
}

################################################################
##         Auswertung Forecast Daten
################################################################
sub extractForecastData($$) {
  my ($hash,$forecast) = @_;
  my $name = $hash->{NAME};
  
  my $dl = AttrVal($name, "detailLevel", 1);
  
  if($dl <= 1) {
      return;
  }
   
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  $year    += 1900;
  $mon     += 1;
  my $today = "$year-".sprintf("%02d", $mon)."-".sprintf("%02d", $mday)."T";

  my $PV_sum     = 0;
  my $consum_sum = 0;
  my $sum        = 0;
  
  readingsBeginUpdate($hash);

  my $plantOid = $forecast->{'ForecastTimeframes'}->{'PlantOid'};

  # Counter for forecast objects
  my $obj_nr = 0;

  # The next few hours...
  my %nextFewHoursSum = ("PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0);

  # Rest of the day...
  my %restOfDaySum = ("PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0);

  # Tomorrow...
  my %tomorrowSum = ("PV" => 0, "Consumption" => 0, "Total" => 0, "ConsumpRcmd" => 0);

  # Get the current day (for 2016-02-26, this is 26)
  my $current_day = (localtime)[3];

  # Loop through all forecast objects
  # Energie wird als "J" geliefert, Wh = J / 3600
  foreach my $fc_obj (@{$forecast->{'ForecastSeries'}}) {
      # Example for DateTime: 2016-02-15T23:00:00
      my $fc_datetime = $fc_obj->{'TimeStamp'}->{'DateTime'};

      # Calculate Unix timestamp (month begins at 0, year at 1900)
      my ($fc_year, $fc_month, $fc_day, $fc_hour) = $fc_datetime =~ /^(\d\d\d\d)-(\d\d)-(\d\d)T(\d\d):00:00$/;
      my $fc_uts          = POSIX::mktime( 0, 0, $fc_hour,  $fc_day, $fc_month - 1, $fc_year - 1900 );
      my $fc_diff_seconds = $fc_uts - time + 3600;  # So we go above 0 for the current hour                                                                        
      my $fc_diff_hours   = int( $fc_diff_seconds / 3600 );

      # Don't use old data
      next if $fc_diff_seconds < 0;

      # Sum up for the next few hours (4 hours total, this is current hour plus the next 3 hours)
      if ($obj_nr < 4) {
         $nextFewHoursSum{'PV'}            += $fc_obj->{'PvMeanPower'}->{'Amount'};
         $nextFewHoursSum{'Consumption'}   += $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600;
         $nextFewHoursSum{'Total'}         += $fc_obj->{'PvMeanPower'}->{'Amount'} - $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600;
         $nextFewHoursSum{'ConsumpRcmd'}   += $fc_obj->{'IsConsumptionRecommended'} ? 1 : 0;
      }

      # If data is for the rest of the current day
      if ( $current_day == $fc_day ) {
         $restOfDaySum{'PV'}            += $fc_obj->{'PvMeanPower'}->{'Amount'};
         $restOfDaySum{'Consumption'}   += $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600;
         $restOfDaySum{'Total'}         += $fc_obj->{'PvMeanPower'}->{'Amount'} - $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600;
         $restOfDaySum{'ConsumpRcmd'}   += $fc_obj->{'IsConsumptionRecommended'} ? 1 : 0;
      }
      
      # If data is for the next day (quick and dirty: current day different from this object's day)
      # Assuming only the current day and the next day are returned from Sunny Portal
      if ( $current_day != $fc_day ) {
         $tomorrowSum{'PV'}            += $fc_obj->{'PvMeanPower'}->{'Amount'} if(exists($fc_obj->{'PvMeanPower'}->{'Amount'}));
         $tomorrowSum{'Consumption'}   += $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600;
         $tomorrowSum{'Total'}         += $fc_obj->{'PvMeanPower'}->{'Amount'} - $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600 if ($fc_obj->{'PvMeanPower'}->{'Amount'});
         $tomorrowSum{'ConsumpRcmd'}   += $fc_obj->{'IsConsumptionRecommended'} ? 1 : 0;
      }
      
      # Update values in Fhem if less than 24 hours in the future
      if($dl >= 2) {
          if ($obj_nr < 24) {
              my $time_str = "ThisHour";
              $time_str = "NextHour".sprintf("%02d", $obj_nr) if($fc_diff_hours>0);
              if($time_str =~ /NextHour/ && $dl >= 4) {
                  readingsBulkUpdate( $hash, "L4_${time_str}_Time", UTC2LocalString($hash,$fc_obj->{'TimeStamp'}->{'DateTime'}) );
                  readingsBulkUpdate( $hash, "L4_${time_str}_PvMeanPower", int( $fc_obj->{'PvMeanPower'}->{'Amount'} ) );
                  readingsBulkUpdate( $hash, "L4_${time_str}_Consumption", int( $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600 ) );
                  readingsBulkUpdate( $hash, "L4_${time_str}_IsConsumptionRecommended", ($fc_obj->{'IsConsumptionRecommended'} ? "yes" : "no") );
                  readingsBulkUpdate( $hash, "L4_${time_str}", int( $fc_obj->{'PvMeanPower'}->{'Amount'} - $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600 ) );
              }
              if($time_str =~ /ThisHour/ && $dl >= 2) {
                  readingsBulkUpdate( $hash, "L2_${time_str}_Time", UTC2LocalString($hash,$fc_obj->{'TimeStamp'}->{'DateTime'}) );
                  readingsBulkUpdate( $hash, "L2_${time_str}_PvMeanPower", int( $fc_obj->{'PvMeanPower'}->{'Amount'} ) );
                  readingsBulkUpdate( $hash, "L2_${time_str}_Consumption", int( $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600 ) );
                  readingsBulkUpdate( $hash, "L2_${time_str}_IsConsumptionRecommended", ($fc_obj->{'IsConsumptionRecommended'} ? "yes" : "no") );
                  readingsBulkUpdate( $hash, "L2_${time_str}", int( $fc_obj->{'PvMeanPower'}->{'Amount'} - $fc_obj->{'ConsumptionForecast'}->{'Amount'} / 3600 ) );
              }
          }
      }

      # Increment object counter
      $obj_nr++;
  }
  
  if($dl >= 2) {
      readingsBulkUpdate($hash, "L2_Next04Hours-Consumption",              int( $nextFewHoursSum{'Consumption'} ) );
      readingsBulkUpdate($hash, "L2_Next04Hours-PV",                       int( $nextFewHoursSum{'PV'}          ) );
      readingsBulkUpdate($hash, "L2_Next04Hours-Total",                    int( $nextFewHoursSum{'Total'}       ) );
      readingsBulkUpdate($hash, "L2_Next04Hours-IsConsumptionRecommended", int( $nextFewHoursSum{'ConsumpRcmd'} ) );
      readingsBulkUpdate($hash, "next04hours_state",                       int( $nextFewHoursSum{'PV'} ) );
  }

  if($dl >= 3) {
      readingsBulkUpdate($hash, "L3_RestOfDay-Consumption",                int( $restOfDaySum{'Consumption'} ) );
      readingsBulkUpdate($hash, "L3_RestOfDay-PV",                         int( $restOfDaySum{'PV'}          ) );
      readingsBulkUpdate($hash, "L3_RestOfDay-Total",                      int( $restOfDaySum{'Total'}       ) );
      readingsBulkUpdate($hash, "L3_RestOfDay-IsConsumptionRecommended",   int( $restOfDaySum{'ConsumpRcmd'} ) );

      readingsBulkUpdate($hash, "L3_Tomorrow-Consumption",                 int( $tomorrowSum{'Consumption'} ) );
      readingsBulkUpdate($hash, "L3_Tomorrow-PV",                          int( $tomorrowSum{'PV'}          ) );
      readingsBulkUpdate($hash, "L3_Tomorrow-Total",                       int( $tomorrowSum{'Total'}       ) );
      readingsBulkUpdate($hash, "L3_Tomorrow-IsConsumptionRecommended",    int( $tomorrowSum{'ConsumpRcmd'} ) );
  }
  
  if($dl >= 4) {  
      readingsBulkUpdate($hash,"L4_plantOid",$plantOid);
  }

  readingsEndUpdate($hash, 1);

return;
}

################################################################
##         Auswertung Wetterdaten
################################################################
sub extractWeatherData($$) {
  my ($hash,$weather) = @_;
  my $name = $hash->{NAME};
  my ($tsymbol,$ttoday,$ttomorrow);
  
  my $dl = AttrVal($name, "detailLevel", 1);
  
  readingsBeginUpdate($hash);
  
  for my $k (keys %$weather) {
      my $new_val = ""; 
      if (defined $weather->{$k}) {
          Log3 $name, 4, "$name - Weatherdata content \"$k\": ".($weather->{$k});
          if ($weather->{$k} =~ m/HASH/i) {
              my $ih = $weather->{$k};
              for my $i (keys %$ih) {
                  my $hd0 = $weather->{$k}{$i};
                  if(!$hd0) {
                      next;
                  }
                  chomp $hd0;
                  $hd0 =~ s/[;']//g;
                  $hd0 = ($hd0 =~ /^undef$/)?"none":$hd0;
                  $hd0 = encode("utf8", $hd0);
                  Log3 $name, 4, "$name - Weatherdata \"$k $i\": $hd0";
                  next if($i =~ /^WeatherIcon$/);
                  $new_val = $hd0;

                  if ($new_val) {
                      if($i =~ /^TemperatureSymbol$/) {
                          $tsymbol = $new_val;
                          next;
                      }
                      if($i =~ /^Temperature$/) {
                          if($k =~ /^today$/) {
                              $ttoday = sprintf("%.1f",$new_val);
                          }
                          if($k =~ /^tomorrow$/) {
                              $ttomorrow = sprintf("%.1f",$new_val);
                          }                          
                          next;
                      }                      
                      
                      Log3 $name, 4, "$name -> ${k}_${i} - $new_val";
                      readingsBulkUpdate($hash, "L1_${k}_${i}", $new_val);
                  }
              }
		  }
      }
  }
  
  readingsBulkUpdate($hash, "L1_today_Temperature", "$ttoday $tsymbol") if($ttoday && $tsymbol);
  readingsBulkUpdate($hash, "L1_tomorrow_Temperature", "$ttomorrow $tsymbol") if($ttomorrow && $tsymbol);
  
  readingsEndUpdate($hash, 1); 

return;
}

################################################################
##                     Auswertung Anlagendaten
################################################################
sub extractPlantData($$) {
  my ($hash,$forecast) = @_;
  my $name = $hash->{NAME};
  my ($amount,$unit);
  
  my $dl = AttrVal($name, "detailLevel", 1);
  if($dl <= 1) {
      return;
  }
  
  readingsBeginUpdate($hash);
  
  my $ppp = $forecast->{'PlantPeakPower'};
  if($ppp && $dl >= 2) {
      $amount = $forecast->{'PlantPeakPower'}{'Amount'}; 
	  $unit   = $forecast->{'PlantPeakPower'}{'StandardUnit'}{'Symbol'}; 
      Log3 $name, 4, "$name - Plantdata \"PlantPeakPower Amount\": $amount";
	  Log3 $name, 4, "$name - Plantdata \"PlantPeakPower Symbol\": $unit";
  }

  readingsBulkUpdate($hash, "L2_PlantPeakPower", "$amount $unit"); 
  
  readingsEndUpdate($hash, 1); 
  
return;
}

################################################################
##                     Auswertung Consumer Data
################################################################
sub extractConsumerData($$) {
  my ($hash,$forecast) = @_;
  my $name = $hash->{NAME};
  my %consumers;
  my ($key,$val);
  
  my $dl = AttrVal($name, "detailLevel", 1);
  if($dl <= 1) {
      return;
  }
  
  readingsBeginUpdate($hash);
  
  # Schleife über alle Consumer Objekte
  my $i = 0;
  foreach my $c (@{$forecast->{'Consumers'}}) {
      $consumers{"${i}_ConsumerName"} = encode("utf8", $c->{'ConsumerName'} );
      $consumers{"${i}_ConsumerOid"}  = $c->{'ConsumerOid'};
      $i++;
  }
  
  if(%consumers && $forecast->{'ForecastTimeframes'}) {
      # es sind Vorhersagen zu geplanten Verbraucherschaltzeiten vorhanden
      foreach my $c (@{$forecast->{'ForecastTimeframes'}{'PlannedTimeFrames'}}) {
          my $deviceOid      = $c->{'DeviceOid'};   
          my $timeFrameStart = UTC2LocalString($hash,$c->{'TimeFrameStart'}{'DateTime'});  # wandele UTC Time zu lokaler Zeit        
          my $timeFrameEnd   = UTC2LocalString($hash,$c->{'TimeFrameEnd'}{'DateTime'});    # wandele UTC Time zu lokaler Zeit
          my $tz             = $c->{'TimeFrameStart'}{'Kind'};
          foreach my $k (keys(%consumers)) {
               $val = $consumers{$k};
               if($val eq $deviceOid) {
                   $k      =~ /^(\d+)_.*$/;
                   my $lfn = $1;
                   # $consumer = $consumers{"${lfn}_ConsumerName"};
                   $consumers{"${lfn}_PlannedOpTimeStart"} = $timeFrameStart;
                   $consumers{"${lfn}_PlannedOpTimeEnd"}   = $timeFrameEnd;
               }
          }          
      }
  
  
  }

  if(%consumers) {
      foreach my $key (keys(%consumers)) {
          Log3 $name, 4, "$name - Consumer data \"$key\": ".$consumers{$key};
          if($key =~ /ConsumerName/ && $dl >= 3) {
               $key    =~ /^(\d+)_.*$/;
               my $lfn = $1; 
               my $cn  = $consumers{"${lfn}_ConsumerName"};            # Verbrauchername
               $cn     = substUmlauts($cn);                            # evtl. Umlaute im Verbrauchernamen ersetzen
               my $pos = $consumers{"${lfn}_PlannedOpTimeStart"};      # geplanter Start
               my $poe = $consumers{"${lfn}_PlannedOpTimeEnd"};        # geplantes Ende
               my $rb  = "L3_${cn}_PlannedOpTimeBegin"; 
               my $re  = "L3_${cn}_PlannedOpTimeEnd";
			   my $rp  = "L3_${cn}_Planned";
               if($pos) {             
                   readingsBulkUpdate($hash, $rb, $pos); 
                   readingsBulkUpdate($hash, $rp, "yes");  				   
               } else {
                   readingsBulkUpdate($hash, $rb, "undefined"); 
				   readingsBulkUpdate($hash, $rp, "no");  
               }   
               if($poe) {             
                   readingsBulkUpdate($hash, $re, $poe);          
               } else {
                   readingsBulkUpdate($hash, $re, "undefined");
               }                  
          }
      }
  }
  
  readingsEndUpdate($hash, 1); 
  
return;
} 

################################################################
# sortiert eine Liste von Versionsnummern x.x.x
# Schwartzian Transform and the GRT transform
# Übergabe: "asc | desc",<Liste von Versionsnummern>
################################################################
sub sortVersionNum (@) {
  my ($sseq,@versions) = @_;

  my @sorted = map {$_->[0]}
			   sort {$a->[1] cmp $b->[1]}
			   map {[$_, pack "C*", split /\./]} @versions;
			 
  @sorted = map {join ".", unpack "C*", $_}
            sort
            map {pack "C*", split /\./} @versions;
  
  if($sseq eq "desc") {
      @sorted = reverse @sorted;
  }
  
return @sorted;
}

################################################################
#               Versionierungen des Moduls setzen
#  Die Verwendung von Meta.pm und Packages wird berücksichtigt
################################################################
sub setVersionInfo($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (sortTopicNum("desc",keys %vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {
	  # META-Daten sind vorhanden
	  $modules{$type}{META}{version} = "v".$v;              # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{SMAPortal}{META}}
	  if($modules{$type}{META}{x_version}) {                                                                             # {x_version} ( nur gesetzt wenn $Id: ... $ im Kopf komplett! vorhanden )
		  $modules{$type}{META}{x_version} =~ s/1.1.1/$v/g;
	  } else {
		  $modules{$type}{META}{x_version} = $v; 
	  }
	  return $@ unless (FHEM::Meta::SetInternals($hash));                                                                # FVERSION wird gesetzt ( nur gesetzt wenn $Id: ... $ im Kopf komplett! vorhanden )
	  if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {
	      # es wird mit Packages gearbeitet -> Perl übliche Modulversion setzen
		  # mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
	      use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );                                          
      }
  } else {
	  # herkömmliche Modulstruktur
	  $hash->{VERSION} = $v;
  }
  
return;
}

################################################################
#                 delete Readings
#   $dl = detailLevel ab dem das Reading gelöscht werden soll 
################################################################
sub delread($;$) {
  my ($hash,$dl) = @_;
  my $name   = $hash->{NAME};
  my @allrds = keys%{$defs{$name}{READINGS}};
 
  if($dl) {
      # Readings ab dem angegebenen Detail-Level löschen
      foreach my $key(@allrds) {
          $key =~ m/^L(\d)_.*$/;     
          if($1 && $1 >= $dl) {
              delete($defs{$name}{READINGS}{$key});
          }         
      }
      return;
  } 

  foreach my $key(@allrds) {
      delete($defs{$name}{READINGS}{$key}) if($key ne "state");
  }

return;
}

################################################################
#                 analysiere Livedaten
################################################################
sub analivedat($$) {
  my ($hash,$lc) = @_;
  my $name       = $hash->{NAME};
  my ($reread,$retry) = (0,0);

  my $livedata_content = decode_json($lc);
  for my $k (keys %$livedata_content) {
      my $new_val = "";
      
      if (defined $livedata_content->{$k}) {
          if (($livedata_content->{$k} =~ m/ARRAY/i) || ($livedata_content->{$k} =~ m/HASH/i)) {
              if($livedata_content->{$k} =~ m/ARRAY/i) {
                  my $hd0 = Dumper($livedata_content->{$k}[0]);
                  if(!$hd0) {
                      next;
                  }
                  chomp $hd0;
                  $hd0 =~ s/[;']//g;
                  $hd0 = ($hd0 =~ /^undef$/)?"none":$hd0;
                  # Log3 $name, 4, "$name - livedata ARRAY content \"$k\": $hd0";
                  $new_val = $hd0;
              }
		  } else {
              $new_val = $livedata_content->{$k};
          }

          if ($new_val && $k !~ /__type/i) {
			  if($k =~ /InfoMessages/ && $new_val =~ /.*login to SMA-Portal successful.*/) {
			      # Login war erfolgreich, Daten neu lesen
			      Log3 $name, 3, "$name - get data again";
				  $reread = 1;
			  }
			  if($k =~ /ErrorMessages/ && $new_val =~ /.*The current data cannot be retrieved from the PV system. Check the cabling and configuration of the following energy meters.*/) {
			      # Energiedaten konnten nicht ermittelt werden, Daten neu lesen mit Zeitverzögerung
			      Log3 $name, 3, "$name - The current data cannot be retrieved from PV system, get data again.";
				  $retry = 1;
			  }
			  if($k =~ /ErrorMessages/ && $new_val =~ /.*Communication with the Sunny Home Manager is currently not possible.*/) {
			      # Energiedaten konnten nicht ermittelt werden, Daten neu lesen mit Zeitverzögerung
			      Log3 $name, 3, "$name - Communication with the Sunny Home Manager currently impossible, get data again.";
				  $retry = 1;
			  }
          }
      }
  }
  
return ($reread,$retry);
}

################################################################
#                    Restart get Data
################################################################
sub retrygetdata($) {
  my ($hash)  = @_;
  my $name    = $hash->{NAME};
  my $timeout = AttrVal($name, "timeout", 30);

  $hash->{HELPER}{RUNNING_PID} = BlockingCall("FHEM::SMAPortal::GetData", $name, "FHEM::SMAPortal::ParseData", $timeout, "FHEM::SMAPortal::ParseAborted", $hash);
  $hash->{HELPER}{RUNNING_PID}{loglevel} = 5 if($hash->{HELPER}{RUNNING_PID});  # Forum #77057
	  
return;
}

################################################################
#             UTC in lokale Zeit umwandeln
################################################################
sub UTC2LocalString($$) {
  my ($hash,$t) = @_;
  $t            =~ s/T/ /;
  my ($datehour, $rest) = split(/:/,$t,2);
  my ($year, $month, $day, $hour) = $datehour =~ /(\d+)-(\d\d)-(\d\d)\s+(\d\d)/;
  
  #  proto: $time = timegm($sec,$min,$hour,$mday,$mon,$year);
  my $epoch = timegm (0,0,$hour,$day,$month-1,$year);
  
  #  proto: ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  my ($lyear,$lmonth,$lday,$lhour,$isdst) = (localtime($epoch))[5,4,3,2,-1];
  
  $lyear += 1900;                  # year is 1900 based
  $lmonth++;                       # month number is zero based

  if(AttrVal("global","language","EN") eq "DE") {
	  return (sprintf("%02d.%02d.%04d %02d:%s", $lday,$lmonth,$lyear,$lhour,$rest));
  } else {
	  return (sprintf("%04d-%02d-%02d %02d:%s", $lyear,$lmonth,$lday,$lhour,$rest));
  }
}

###############################################################################
#              Umlaute für Readingerstellung ersetzen 
###############################################################################
sub substUmlauts ($) { 
  my ($txt) = @_;

  $txt =~ s/ß/ss/g;
  $txt =~ s/ä/ae/g;
  $txt =~ s/ö/oe/g;
  $txt =~ s/ü/ue/g;
  $txt =~ s/Ä/Ae/g;
  $txt =~ s/Ö/Oe/g;
  $txt =~ s/Ü/Ue/g;     
  
return($txt);
}

###############################################################################
#                  Subroutine für WebLink-Device
###############################################################################
sub PortalAsHtml ($) { 
  my ($name) = @_;
  my $hash   = $defs{$name};
  return "Device \"$name\" doesn't exist !" if(!$hash);
  
  if(AttrVal($name, "detailLevel", 1) != 4) {
      return "The attribute \"detailLevel\" of device \"$name\" has to be set to level \"4\" !";
  }

  my $pv4h = ReadingsNum($name,"L2_Next04Hours-PV", "");
  my $pvRe = ReadingsNum($name,"L3_RestOfDay-PV", ""); 
  my $pvTo = ReadingsNum($name,"L3_Tomorrow-PV", "");
  
  my $pv00 = ReadingsNum($name,"L2_ThisHour_PvMeanPower", undef);
  my $pv01 = ReadingsNum($name,"L4_NextHour01_PvMeanPower",undef);
  my $pv02 = ReadingsNum($name,"L4_NextHour02_PvMeanPower",undef);
  my $pv03 = ReadingsNum($name,"L4_NextHour03_PvMeanPower",undef);
  my $pv04 = ReadingsNum($name,"L4_NextHour04_PvMeanPower",undef);
  my $pv05 = ReadingsNum($name,"L4_NextHour05_PvMeanPower",undef);
  my $pv06 = ReadingsNum($name,"L4_NextHour06_PvMeanPower",undef);
  my $pv07 = ReadingsNum($name,"L4_NextHour07_PvMeanPower",undef);
  my $pv08 = ReadingsNum($name,"L4_NextHour08_PvMeanPower",undef);
  my $pv09 = ReadingsNum($name,"L4_NextHour09_PvMeanPower",undef);
  my $pv10 = ReadingsNum($name,"L4_NextHour10_PvMeanPower",undef);
  my $pv11 = ReadingsNum($name,"L4_NextHour11_PvMeanPower",undef);
  my $pv12 = ReadingsNum($name,"L4_NextHour12_PvMeanPower",undef);
  my $pv13 = ReadingsNum($name,"L4_NextHour13_PvMeanPower",undef);
  my $pv14 = ReadingsNum($name,"L4_NextHour14_PvMeanPower",undef);
  my $pv15 = ReadingsNum($name,"L4_NextHour15_PvMeanPower",undef);
  my $pv16 = ReadingsNum($name,"L4_NextHour16_PvMeanPower",undef);
  my $pv17 = ReadingsNum($name,"L4_NextHour17_PvMeanPower",undef);
  my $pv18 = ReadingsNum($name,"L4_NextHour18_PvMeanPower",undef);
  my $pv19 = ReadingsNum($name,"L4_NextHour19_PvMeanPower",undef);
  my $pv20 = ReadingsNum($name,"L4_NextHour20_PvMeanPower",undef);
  my $pv21 = ReadingsNum($name,"L4_NextHour21_PvMeanPower",undef);
  my $pv22 = ReadingsNum($name,"L4_NextHour22_PvMeanPower",undef);
  my $pv23 = ReadingsNum($name,"L4_NextHour23_PvMeanPower",undef);
  return "Awaiting level 4 data ... " if(!defined $pv01);
  
  my $is00 = ReadingsVal($name,"L2_ThisHour_IsConsumptionRecommended",undef);
  my $is01 = ReadingsVal($name,"L4_NextHour01_IsConsumptionRecommended",undef);
  my $is02 = ReadingsVal($name,"L4_NextHour02_IsConsumptionRecommended",undef);
  my $is03 = ReadingsVal($name,"L4_NextHour03_IsConsumptionRecommended",undef);
  my $is04 = ReadingsVal($name,"L4_NextHour04_IsConsumptionRecommended",undef);
  my $is05 = ReadingsVal($name,"L4_NextHour05_IsConsumptionRecommended",undef);
  my $is06 = ReadingsVal($name,"L4_NextHour06_IsConsumptionRecommended",undef);
  my $is07 = ReadingsVal($name,"L4_NextHour07_IsConsumptionRecommended",undef);
  my $is08 = ReadingsVal($name,"L4_NextHour08_IsConsumptionRecommended",undef);
  my $is09 = ReadingsVal($name,"L4_NextHour09_IsConsumptionRecommended",undef);
  my $is10 = ReadingsVal($name,"L4_NextHour10_IsConsumptionRecommended",undef);
  my $is11 = ReadingsVal($name,"L4_NextHour11_IsConsumptionRecommended",undef);
  my $is12 = ReadingsVal($name,"L4_NextHour12_IsConsumptionRecommended",undef);
  my $is13 = ReadingsVal($name,"L4_NextHour13_IsConsumptionRecommended",undef);
  my $is14 = ReadingsVal($name,"L4_NextHour14_IsConsumptionRecommended",undef);
  my $is15 = ReadingsVal($name,"L4_NextHour15_IsConsumptionRecommended",undef);
  my $is16 = ReadingsVal($name,"L4_NextHour16_IsConsumptionRecommended",undef);
  my $is17 = ReadingsVal($name,"L4_NextHour17_IsConsumptionRecommended",undef);
  my $is18 = ReadingsVal($name,"L4_NextHour18_IsConsumptionRecommended",undef);
  my $is19 = ReadingsVal($name,"L4_NextHour19_IsConsumptionRecommended",undef);
  my $is20 = ReadingsVal($name,"L4_NextHour20_IsConsumptionRecommended",undef);
  my $is21 = ReadingsVal($name,"L4_NextHour21_IsConsumptionRecommended",undef);
  my $is22 = ReadingsVal($name,"L4_NextHour22_IsConsumptionRecommended",undef);
  my $is23 = ReadingsVal($name,"L4_NextHour23_IsConsumptionRecommended",undef);
  return "Awaiting level 4 data ... " if(!defined $is01);
  
  my $time00 = strftime("%H",localtime);
  my $time01 = strftime("%H",localtime(time+1*60*60));
  my $time02 = strftime("%H",localtime(time+2*60*60));
  my $time03 = strftime("%H",localtime(time+3*60*60)); 
  my $time04 = strftime("%H",localtime(time+4*60*60)); 
  my $time05 = strftime("%H",localtime(time+5*60*60)); 
  my $time06 = strftime("%H",localtime(time+6*60*60));
  my $time07 = strftime("%H",localtime(time+7*60*60));
  my $time08 = strftime("%H",localtime(time+8*60*60));
  my $time09 = strftime("%H",localtime(time+9*60*60));
  my $time10 = strftime("%H",localtime(time+10*60*60));
  my $time11 = strftime("%H",localtime(time+11*60*60));
  my $time12 = strftime("%H",localtime(time+12*60*60));
  my $time13 = strftime("%H",localtime(time+13*60*60));
  my $time14 = strftime("%H",localtime(time+14*60*60));
  my $time15 = strftime("%H",localtime(time+15*60*60));
  my $time16 = strftime("%H",localtime(time+16*60*60));
  my $time17 = strftime("%H",localtime(time+17*60*60));
  my $time18 = strftime("%H",localtime(time+18*60*60));
  my $time19 = strftime("%H",localtime(time+19*60*60));
  my $time20 = strftime("%H",localtime(time+20*60*60));
  my $time21 = strftime("%H",localtime(time+21*60*60));
  my $time22 = strftime("%H",localtime(time+22*60*60));
  my $time23 = strftime("%H",localtime(time+23*60*60));

  # Konfiguration des maximal übergebenen Werts (hier wäre der höchste zu erwartende Wert = 8020)
  my $maxValue = ReadingsNum($name,"L2_PlantPeakPower", 8020);
  # Konfiguration den Platz zwischen den Balken (hier wäre der höchste zu erwartende Wert = 30)
  my $space = 2;
  # Konfiguration des breite der Balken (hier wäre der höchste zu erwartende Wert = 30)
  my $width = 24;
  # Konfiguration des höhe der Balken  (hier wäre der höchste zu erwartende Wert = 160)
  my $height = 160;
  # Konfiguration der Farbe oben (hier wäre der höchste zu erwartende Wert = "FFFFFF")
  my $color1 = "#FFFFFF";
  # Konfiguration der Farbe des Wertes (hier wäre der höchste zu erwartende Wert = "4B9C8A")
  my $color2 = "#4B9C8A";

  #### Tabelle
  my $ret = "";
  $ret .= "<html><table border=2 bordercolor='darkgreen' cellspacing=1><tr>";
  $ret .= "<td colspan=24 style='text-align:center; font-weight:bold; padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>Prognose der nächsten 4 Stunden: ".($pv4h)." Wh / Rest des Tages: ".($pvRe)." Wh / Morgen: ".($pvTo)." Wh</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time00."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is00."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv00)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv00."</td></tr>";
  $ret .= "<tr style='height:".($pv00/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time01."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is01."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv01)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv01."</td></tr>";
  $ret .= "<tr style='height:".($pv01/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time02."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is02."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv02)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv02."</td></tr>";
  $ret .= "<tr style='height:".($pv02/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time03."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is03."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv03)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv03."</td></tr>";
  $ret .= "<tr style='height:".($pv03/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time04."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is04."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv04)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv04."</td></tr>";
  $ret .= "<tr style='height:".($pv04/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time05."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is05."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv05)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv05."</td></tr>";
  $ret .= "<tr style='height:".($pv05/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";

  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";

  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time06."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is06."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv06)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv06."</td></tr>";
  $ret .= "<tr style='height:".($pv06/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";

  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";

  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time07."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is07."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv07)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv07."</td></tr>";
  $ret .= "<tr style='height:".($pv07/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";

  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";

  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time08."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is08."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv08)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv08."</td></tr>";
  $ret .= "<tr style='height:".($pv08/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";

  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";

  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time09."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is09."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv09)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv09."</td></tr>";
  $ret .= "<tr style='height:".($pv09/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time10."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is10."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv10)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv10."</td></tr>";
  $ret .= "<tr style='height:".($pv10/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";

  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time11."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is11."</td>";
  $ret .= "</tr>";
  $ret .= "<tr align=center style='height:".(($maxValue-$pv11)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv11."</td></tr>";
  $ret .= "<tr style='height:".($pv11/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time12."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is12."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv12)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv12."</td></tr>";
  $ret .= "<tr style='height:".($pv12/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time13."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is13."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv13)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv13."</td></tr>";
  $ret .= "<tr style='height:".($pv13/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time14."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is14."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv14)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv14."</td></tr>";
  $ret .= "<tr style='height:".($pv14/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time15."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is15."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv15)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv15."</td></tr>";
  $ret .= "<tr style='height:".($pv15/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time16."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is16."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv16)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv16."</td></tr>";
  $ret .= "<tr style='height:".($pv16/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time17."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is17."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv17)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv17."</td></tr>";
  $ret .= "<tr style='height:".($pv17/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time18."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is18."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv18)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv18."</td></tr>";
  $ret .= "<tr style='height:".($pv18/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time19."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is19."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv19)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv19."</td></tr>";
  $ret .= "<tr style='height:".($pv19/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time20."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is20."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv20)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv20."</td></tr>";
  $ret .= "<tr style='height:".($pv20/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time21."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is21."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv21)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv21."</td></tr>";
  $ret .= "<tr style='height:".($pv21/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time22."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is22."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv22)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv22."</td></tr>";
  $ret .= "<tr style='height:".($pv22/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;width:".($width)."px'>";
  
  $ret .= "<table border=0 bordercolor='darkgreen' cellspacing=1>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$time23."</td>";
  $ret .= "</tr>";
  $ret .= "<tr>";
  $ret .= "<td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$is23."</td>";
  $ret .= "</tr>";
  $ret .= "<tr style='height:".(($maxValue-$pv23)/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color1."'>".$pv23."</td></tr>";
  $ret .= "<tr style='height:".($pv23/$maxValue*$height)."px'><td style='padding-right:".($space)."px;padding-left:".($space)."px;background-color:".$color2."'></td></tr>";
  $ret .= "</table>";
  
  $ret .= "</td>";
  $ret .= "</tr></table></html>";
    
return($ret);
}

1;

=pod
=encoding utf8
=item summary    Module for communication with the SMA-Portal
=item summary_DE Modul zur Kommunikation mit dem SMA-Portal

=begin html

<a name="SMAPortal"></a>
<h3>SMAPortal</h3>

<ul>
  <br>
  
  Is coming soon ...

</ul>


=end html
=begin html_DE

<a name="SMAPortal"></a>
<h3>SMAPortal</h3>
<ul>

   Mit diesem Modul können Daten aus dem <a href="https://www.sunnyportal.com">SMA-Portal</a> abgerufen werden.
   Momentan sind es: <br><br>
   <ul>
    <ul>
     <li>Live-Daten (Verbrauch und PV-Erzeugung) </li>
     <li>Batteriedaten (In/Out) </li>
     <li>Wetter-Daten von SMA für den Anlagenstandort </li>
     <li>Prognosedaten (Verbrauch und PV-Erzeugung) inklusive Verbraucherempfehlung </li>
     <li>die durch den Sunny Home Manager geplanten Schaltzeiten von Verbrauchern (sofern vorhanden) </li>
    </ul> 
   </ul>
   <br>
   
   <b>Vorbereitung </b> <br><br>
    
   <ul>   
    Dieses Modul nutzt das Perl-Modul JSON welches üblicherweise nachinstalliert werden muss. <br>
	Auf Debian-Linux basierenden Systemen kann es installiert werden mit: <br><br>
    
    <code>sudo apt-get install libjson-perl</code>      <br><br>
    
    Überblick über die Perl-Module welche von SMAPortal genutzt werden: <br><br>
    
    POSIX           <br>
    JSON            <br>
    Data::Dumper    <br>                  
    Time::HiRes     <br>
    Time::Local     <br>
	Blocking        (FHEM-Modul) <br>
    GPUtils         (FHEM-Modul) <br>
    FHEM::Meta      (FHEM-Modul) <br>
	LWP::UserAgent  <br>
	HTTP::Cookies   <br>
    MIME::Base64    <br>
    Encode          <br>
    
    <br><br>  
   </ul>
  
   <a name="SMAPortalDefine"></a>
   <b>Definition</b>
   <ul>
    <br>
    Ein SMAPortal-Device wird definiert mit: <br><br>
	
    <ul>
      <b><code>define &lt;Name&gt; SMAPortal</code></b> <br><br>
    </ul>
   
    Nach der Definition des Devices müssen noch die Zugangsparameter für das SMA-Portal gespeichert werden. 
    Das geschieht mit dem Befehl: <br><br>
   
    <ul> 
     set &lt;Name&gt; credentials &lt;Username&gt; &lt;Passwort&gt;
    </ul>     
   </ul>
   <br><br>   
    
   <a name="SMAPortalSet"></a>
   <b>Set </b>
   <ul>
   <br>
     <ul>
     <li><b> set &lt;name&gt; credentials &lt;username&gt; &lt;password&gt; </b> </li>  
     Setzt Username / Passwort für den Zugriff zum SMA-Portal.   
     </ul>   
     <br><br>
     
     <ul>
     <li><b> set &lt;name&gt; createPortalGraphic </b> </li>  
     Erstellt ein weblink-Device zur grafischen Anzeige der SMA Portaldaten. Das Attribut "detailLevel" muss auf den
     Level 4 gesetzt sein. Der Befehl setzt dieses Attribut automatisch auf den benötigten Wert.     
     </ul> 
   </ul>
   <br><br>
   
   <a name="SMAPortalGet"></a>
   <b>Get</b>
   <ul>
    <br>
    <ul>
      <li><b> get &lt;name&gt; data </b> </li>  
      Mit diesem Befehl werden die Daten aus dem SMA-Portal manuell abgerufen. 
    </ul>
    <br>
    
    <ul>
      <li><b> get &lt;name&gt; storedCredentials </b> </li>  
      Die gespeicherten Anmeldeinformationen (Credentials) werden in einem Popup als Klartext angezeigt.
    </ul>
   </ul>  
   <br><br>
   
   <a name="SMAPortalAttr"></a>
   <b>Attribute</b>
   <ul>
     <br>
     <ul>
       <a name="cookielifetime"></a>
       <li><b>cookielifetime &lt;Sekunden&gt; </b><br>
       Gültigkeitszeitraum für einen empfangenen Cookie (Default: 3000 Sekunden).  
       </li><br>
       
       <a name="cookieLocation"></a>
       <li><b>cookieLocation &lt;Pfad/File&gt; </b><br>
       Angabe von Pfad und Datei zur Abspeicherung des empfangenen Cookies (Default: ./log/mycookies.txt).
       <br><br> 
  
        <ul>
		 <b>Beispiel:</b><br>
         attr &lt;name&gt; cookieLocation ./log/cookies.txt <br>    
        </ul>        
       </li><br>
       
       <a name="detailLevel"></a>
       <li><b>detailLevel </b><br>
       Es wird der Umfang der zu generierenden Daten eingestellt. 
       <br><br>
	
	   <ul>   
	   <table>  
	   <colgroup> <col width=5%> <col width=95%> </colgroup>
		  <tr><td> <b>L1</b>  </td><td>- nur Live-Daten und Wetter-Daten werden generiert. </td></tr>
		  <tr><td> <b>L2</b>  </td><td>- wie L1 und zusätzlich Prognose der aktuellen und nächsten 4 Stunden </td></tr>
		  <tr><td> <b>L3</b>  </td><td>- wie L2 und zusätzlich Prognosedaten des Resttages, des Folgetages und der geplanten Schaltzeiten für Verbraucher </td></tr>
          <tr><td> <b>L4</b>  </td><td>- wie L3 und zusätzlich die detaillierte Prognose der nächsten 24 Stunden </td></tr>
	   </table>
	   </ul>     
	   <br>       
       </li><br>
       
       <a name="disable"></a>
       <li><b>disable</b><br>
       Deaktiviert das Device. </li><br>
       
       <a name="getDataRetries"></a>
       <li><b>getDataRetries &lt;Anzahl&gt; </b><br>
       Anzahl der Wiederholungen (get data) im Fall dass keine Live-Daten vom SMA-Portal geliefert 
       wurden (default: 3). </li><br>

       <a name="interval"></a>
       <li><b>interval &lt;Sekunden&gt; </b><br>
       Zeitintervall zum kontinuierlichen Datenabruf aus dem SMA-Portal (Default: 300 Sekunden). <br>
       Ist "interval = 0" gesetzt, erfolgt kein automatischer Datenabruf und muss mit "get &lt;name&gt; data" manuell
       erfolgen. </li><br>
       
       <a name="showPassInLog"></a>
       <li><b>showPassInLog</b><br>
       Wenn gesetzt, wird das verwendete Passwort im Logfile angezeigt. 
       (default = 0) </li><br>
       
       <a name="timeout"></a>
       <li><b>timeout &lt;Sekunden&gt; </b><br>
       Timeout-Wert für HTTP-Aufrufe zum SMA-Portal (Default: 30 Sekunden).  
       </li><br>
       
       <a name="userAgent"></a>
       <li><b>userAgent &lt;Kennung&gt; </b><br>
       Es kann die User-Agent-Kennung zur Identifikation gegenüber dem Portal angegeben werden.
       <br><br> 
  
        <ul>
		 <b>Beispiel:</b><br>
         attr &lt;name&gt; userAgent Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:65.0) Gecko/20100101 Firefox/65.0 <br>    
        </ul>           
       </li><br>       
   
  
     </ul>
   </ul>
    
    
</ul>

=end html_DE

=for :application/json;q=META.json 76_SMAPortal.pm
{
  "abstract": "Module for communication with the SMA-Portal",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Kommunikation mit dem SMA-Portal"
    }
  },
  "keywords": [
    "sma",
    "photovoltaik",
    "electricity",
    "portal",
    "smaportal"
  ],
  "version": "v1.1.1",
  "release_status": "testing",
  "author": [
    "Heiko Maaz <heiko.maaz@t-online.de>"
  ],
  "x_fhem_maintainer": [
    "DS_Starter"
  ],
  "x_fhem_maintainer_github": [
    "nasseeder1"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "JSON": 0,
        "Encode": 0,
        "POSIX": 0,
        "Data::Dumper": 0,
        "Blocking": 0,
        "GPUtils": 0,
        "Time::HiRes": 0,
        "Time::Local": 0,
        "LWP": 0,
        "HTTP::Cookies": 0,
        "MIME::Base64": 0
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut