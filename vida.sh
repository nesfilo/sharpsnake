session=#Boss
session2=VetadosS2
process=process-115-no_exit

exit_type(){
trap 'echo -en "\n\e[0;32mEl proceso se ha cerrado\n\e[0m"; exit 127' SIGINT
}

exit_type

do_secure_process() {
	secure="process-115-no_exit"
	while true
	do
		sudo lua 'sharp.lua'
		echo -e $process
	for i in 1
	do
		date=$(date +%d/%m/%Y)
		date_timed=$(date +%H:%M:%S)
		echo -en "\n$i\n
Día $date\n
Hora $date_timed
\nERROR (127 - Cierre inesperado)\n
" >> informe.txt

	done
		echo "RESTABLECIDO" >> informe.txt
	done
}

if [ "$1" = "" ]; then
	clear
	sudo tmux kill-session -t $session
	sudo tmux kill-session -t $process
	clear
	sudo tmux new-session -s "$session" -d 'lua sharp.lua'
	sudo tmux attach -t "$session"

fi

if [ "$1" = "adjunto" ]; then
  if [ "$2" == "" ]; then
	clear
	sudo tmux attach -t "$session"
  fi
  if [ "$2" == "vetados" ]; then
        clear
        sudo tmux attach -t "$session2"
  fi
  if [ "$2" == "seguro" ]; then
        clear
        sudo tmux attach -t "$process"
  fi
fi

if [ "$1" = "fin" ]; then
	clear
	sudo tmux kill-session -t $process
	sudo tmux kill-session -t $session
	sudo tmux kill-session -t $session2
fi

if [ "$1" == "$process" ]; then
	do_secure_process
fi

if [ "$1" == "seguro" ]; then
	clear
	sudo tmux kill-session -t $session
	sudo tmux kill-session -t $process
	clear
	sudo tmux new-session -s "$process" -d 'sudo bash run.sh '$process
	echo "Sesión segura iniciada"
	exit
fi
