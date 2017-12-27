#!/bin/bash
#
# jboss
# Autor: Aecio Junior <aeciojr@gmail.com>
# Descrficao: Script para intervencoes nos nodes/jboss de cluster ajp
#
# Observacao: Nenhuma
#
# Versao 1: Criado o script
 
 
# ----------------- Variaveis de Configuracao ------------------ #
PrefixoNodeName=LNXAGENDAMENTOCIVIL
UsuarioRSA=linuxuser
ChaveRSA=/home/$UsuarioRSA/.ssh/id_rsa
# ----------------- Variaveis do Script ------------------ #
JAVA_HOME="/usr/local/java"
JBOSS_HOME="/usr/local/jboss"
#PATH="$PATH:$JAVA_HOME/bin"
INSTANCIA="all"
export LAUNCH_JBOSS_IN_BACKGROUND=true
export JBOSS_PIDFILE="/var/run/jboss/jboss.pid"
if [ ! -d /var/run/jboss ]; then
        mkdir -p /var/run/jboss
        chown jboss:jboss /var/run/jboss
fi
# ----------------- Exports ------------------ #
export JAVA_HOME
export JBOSS_HOME
export PATH
# ----------------- Funcoes ------------------ #
_Usage(){
clear
echo "
Este script trata-se de um fork elaborado pela Central IT para agilizar intervencoes nas instancias de aplicacao deste servico. 
 
**** O original foi mantido para intervencoes locais. *****
 
A proposta deste eh submeter comandos STOP/START/STATUS em todos os nodes do cluster.
 
IMPORTANTE: Este deve ser executado com o usuario \"$UsuarioRSA\" conforme usage:
 
Usage:
 
Intervencoes no Node local:
 
$ sudo /etc/init.d/jboss {stop|start|status|restart}
 
Intervencoes nos Nodes remotos:
 
$ sudo /etc/init.d/jboss            {stop|start|status|restart} {all|00}
    .                .                           .                 .
    .                .                           .                 .
    .                .                           .                 ...... Node (Ex. 01 ou all)
    .                .                           ........................ Operacao
    .                .................................................... Script
    ..................................................................... Executa como superuser
"
}
 
_SSH(){
   local Node="$1"
   local Comando="$2"
   ssh -p7654 -n -T -i $ChaveRSA $UsuarioRSA@$Node "$Comando"
}
 
_Status(){
   local RC=0
 
   if [ $# -eq 1 ]
   then
      local Node=$1
      _SSH $Node "sudo /etc/init.d/jboss status"
   else
      ps aux|grep -v grep |grep java
      netstat -tpln | grep java
      return $RC
   fi
}

_Log(){
   tail -f /usr/local/jboss/server/${INSTANCIA}/log/server.log | \
   awk '/INFO/ {print "\033[32m" $0 "\033[39m"} /ERROR/ {print "\033[31m" $0 "\033[39m"} /WARNING/ {print "\033[33m" $0 "\033[39m"}'
}
 
_Kill(){
   local Signal=$1
   local RC=1
   local Retry=5
   local Count=1
   local Processo=$( pgrep java > /dev/null; echo $? )
   while [ $Processo -eq 0 -a $Count -lt $Retry ]
   do
      local PID="$( ps aux | grep -v grep | grep java | awk '{ print $2 }'|tr -s '\n' ' ' )"
      kill $Signal "$PID"
      let Count++
      sleep 10
      local Processo=$( pgrep java > /dev/null; echo $? )
   done
   local Processo=$( pgrep java > /dev/null; echo $? )
   [[ $Processo -eq 0 ]] || local RC=0
   return $RC
}
 
_StopDefault(){
   local RC=0
   TimeWait=30
   su -c "exec $JBOSS_HOME/bin/shutdown.sh -o 0.0.0.0" jboss
   sleep $TimeWait
   local Processo=$( pgrep java > /dev/null; echo $? )
   if [ $Processo -eq 0 ]; then
      _Kill -15 || local RC=$?
   fi
   if [ $RC -ne 0 ]; then
      sleep $TimeWait
     _Kill -9
     local RC=0
   fi
   return $RC
}
 
_Stop(){
   local RC=0
   if [ $# -eq 1 ]
   then
      local Node=$1
      _SSH $Node "sudo /etc/init.d/jboss stop"
   else
      _StopDefault
      return $RC
   fi
}
 
_Start(){
   local RC=0
 
   if [ $# -eq 1 ]
   then
      local Node=$1
      _SSH $Node "sudo /etc/init.d/jboss start"
   else
      su -c "exec $JBOSS_HOME/bin/run.sh -b 0.0.0.0 -c ${INSTANCIA} &" jboss > /dev/null 2>&1 || local RC=$?
      return $?
   fi
}
 
_Restart(){
   local RC=0
   { _Stop || local RC=$?; } && { _Start || local RC=$?; }
   return $RC
}
 
_TraduzNodeName(){
   local Node=$1
   if [ "$Node" != "ALL" ]
   then
      NodeName=$( grep "${PrefixoNodeName}${Node}" /etc/hosts | cut -d\  -f1 )
   elif [ "$Node" == "ALL" ]
   then
      NodeName="$( grep "${PrefixoNodeName}" /etc/hosts | cut -d\  -f1 )"
   fi
   echo "${NodeName}"
}
 
# ----------------- Inicio do Script ------------------ #
 
Args=$#
if [ $Args -eq 2 ]
then
   Comando=$1
   Node="$( echo $2 | tr [:lower:] [:upper:] )"
 
   case $Node in
      ALL|[0-9][0-9]) { NODE=`_TraduzNodeName $Node`; } ;;
      *) { echo $Usage; exit 1; } ;;
   esac
 
   case $Comando in
      status)  { CMD="_Status";  } ;;
      start)   { CMD="_Start";   } ;;
      stop)    { CMD="_Stop";    } ;;
      log)     { CMD="_Log";     } ;;
      restart) { CMD="_Restart"; } ;;
      *)       { echo Use corretamente os params; exit 1; } ;;
   esac
   echo "${NODE}" | while read N
   do
      HostNameIP=$( grep ${N} /etc/hosts )
      echo "================== ${CMD} - $HostNameIP ================"
      $CMD ${N}
   done
elif [ $Args -eq 1 ]
then
   Comando=$1
   [[ ! -z $2 ]] && Node=$2
   case $Comando in
      status)  { _Status;  } ;;
      start)   { _Start;   } ;;
      stop)    { _Stop;    } ;;
      log)     { _Log;    } ;;
      restart) { _Restart; } ;;
      *)       { echo Use corretamente os params; } ;;
   esac
else
   _Usage
   # echo "Use corretamente os params {start|stop|status}"
fi
 
# ----------------- Fim do Script ------------------ #
