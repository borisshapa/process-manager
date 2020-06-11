#!/bin/bash

stream=false

while read line; do
	if [[ $stream == true ]]; then
		continue
	fi
	cnt_args=$(echo "$line" | awk '{print NF}')
        cnt_args=$((cnt_args-1))

	command=$(echo "$line" | awk '{print $1}')
	case $command in
		list)
			ans=""
			for file in /proc/[0-9]*/cmdline; do
				pid=$(echo "$file" | grep -Eo "[[:digit:]]+")
                                cmdline=$(tr '\0' ' ' < $file | awk '{print $1}')
				cpu=$(cat /proc/$pid/stat | awk '{print $14}')
				if [[ -n "$cmdline" ]]; then
	                                cmdline="($cmdline)"
                                fi

				ans="$ans$cpu \e[96m$pid\e[39m $cmdline\n"
			done
			echo -e "\e[1mPID   (CMDLINE)\e[0m"
			echo -e $ans | sort -n | awk '{print $2 $3}'
			;;
		info)
			if [[ $cnt_args < 1 ]]; then
                                echo -e "\e[91mExpected 1 arguments (SIGNAL, PID), found $cnt_args\e[39m\n"
                                continue
                        fi
			pid=$(echo "$line" | awk '{print $2}')
			if [[ ! $pid =~ [[:digit:]+] ]]; then
                                echo -e "\e[91mPID must be a number\e[39m\n"
                                continue
                        fi
			ppid=$(grep "PPid" "/proc/$pid/status" | awk {'print $2'})
			ppid_cmdline=$(cat /proc/$pid/cmdline 2>/dev/null | awk '{print $1}')
			loginuid=$(cat /proc/$pid/loginuid)
			username="root"
			if [[ $loginuid != 4294967295 ]]; then
				username=$(id -nu $loginuid)	
			fi
			file=$(readlink /proc/$pid/exe)
			dir=$(readlink /proc/$pid/cwd)
			mem=$(cat /proc/$pid/statm | awk '{print $1}')
			mem=$((4 * mem / 1024))
			res="\e[1mParent process:\e[0m \e[96m$ppid\e[39m ($ppid_cmdline)\n`
			     `\e[1mUser:\e[0m $username\n"
			if [[ -n "$file" ]]; then
				res="$res`
				`\e[1mPath to executable file:\e[0m \e[92m$file\e[39m\n"
			fi
			if [[ -n "$dir" ]]; then
                                res="$res`
                                `\e[1mWorking directory:\e[0m \e[92m$dir\e[39m\n"
                        fi
			res="$res`
			    `\e[1mMemory:\e[0m $mem M\n"

			echo -e "$res"
			;;
		find)
			query=$(echo "$line" | awk '{print $2}')
			echo "$query"
			for file in /proc/[0-9]*/cmdline; do
				if grep -q "$query" "$file"; then
					pid=$(echo "$file" | grep -Eo "[[:digit:]]+")
					cmdline=$(tr '\0' ' ' < $file)
					echo -e "\e[96m$pid\e[39m ($cmdline)"
				fi
			done
			echo ""
			;;
		send)
			if [[ $cnt_args < 2 ]]; then
				echo -e "\e[91mExpected 2 arguments (SIGNAL, PID), found $cnt_args\e[39m\n"
				continue
			fi
			signal=$(echo "$line" | awk '{print $2}')
			pid=$(echo "$line" | awk '{print $3}')
			if [[ ! $pid =~ [[:digit:]+] ]]; then
				echo -e "\e[91mPID must be a number\e[39m\n"
				continue
			fi
			kill -s "$signal" "$pid"
			;;
		stream)
			stream=true
			{
			declare -A proc_dict
			declare -A existing_proc

			for i in /proc/[0-9]*/status; do
				state=$(grep "State" "$i" | awk '{print $2}')
				pid=$(grep -w "Pid" "$i" | awk '{print $2}')
				proc_dict[$pid]="$state"
				existing_proc[$pid]=$(cat /proc/$pid/cmdline 2>/dev/null | awk '{print $1}')
			done
			
			while true; do
				sleep 2
				for i in /proc/[0-9]*/status; do
					state=$(grep -s "State" "$i" | awk '{print $2}')
	                       		pid=$(grep -ws "Pid" "$i" | awk '{print $2}')
			
					if [[ -n "$pid" && -n "${proc_dict[$pid]}" && "${proc_dict[$pid]}" != "$state" ]]; then
						cmdline=${existing_proc[$pid]}
						if [[ -n "$cmdline" ]]; then
							cmdline="($cmdline)"
						fi

						if [[ "$state" == "R" ]]; then
							echo -e "process \e[96m$pid\e[39m $cmdline \e[92mstarted\e[39m"
						elif [[ "$state" == "S" ]]; then
							echo -e "process \e[96m$pid\e[39m $cmdline \e[93mfell asleep\e[39m"
						fi
						proc_dict[$pid]="$state"
					fi

					[ -n "$pid" ] && existing_proc[$pid]=""
				done

				for i in "${!existing_proc[@]}"; do
        				if [[ ${existing_proc[$i]} = "" ]]; then
						existing_proc[$i]=$(cat /proc/$i/cmdline 2>/dev/null | awk '{print $1}')
					else
						cmdline=${existing_proc[$i]}
						if [[ -n "$cmdline" ]]; then
							cmdline="($cmdline)"
						fi
						echo -e "process \e[96m$i\e[39m $cmdline \e[91mfinished\e[39m"
						unset proc_dict[$i]
						unset existing_proc[$i]	
					fi
				done
			done
			}&
			bg_pid="$!"
			trap 'stream=false; kill $bg_pid; trap exit SIGINT; echo -e "\n"' SIGINT
			;;
		exit)
			exit
			;;
		help)
			echo -e "\e[1m'\e[95mlist\e[39m' — a list of processes (Line format: 'PID : command');\n`
				`'\e[95minfo <PID>\e[39m' — details of process on PID;\n`
				`'\e[95mfind <QUERY>\e[39m' — a list of processes whose start command contains a request QUERY;\n`
				`'\e[95msend <SIGNAL> <PID>\e[39m' — sending a signal SIGNAL to the process PID;\n`
				`'\e[95mstream\e[39m' — enable tracking mode. The console displays events of the form:\n`
				`	'process 12346 (bash script.sh) started'\n`
				`	'process 12177 (/usr/bin/gnome-terminal) finished'\n`
				`('Ctrl+C' to exit tracking mode);\n`
				`'\e[95mhelp\e[39m'\n`
				`'\e[95mexit\e[39m'\n\e[0m"
			;;
		*)
			echo -e "$command: \e[91mcommand not found\e[39m\n`
				`\e[1mTry 'help' for more information\e[0m\n"
	esac
done
