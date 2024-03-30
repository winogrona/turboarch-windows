export TA_ROOT="/opt/turboarch"

LOGGING_FD=2

say() {
	echo -e "$*" >&$LOGGING_FD 
}

sayn() {
	echo -ne "$*" >&$LOGGING_FD
}

log() {
	$LOGGING && say "[LOG]: $*"
}

info() {
	say "\e[34;1minfo\e[0;1m: $*\e[0m"
}

error() {
	say "\e[31;1merror\e[0;1m: $*\e[0m"
}

warning() {
	say "\e[33;1mwarning\e[0;1m: $*\e[0m"
}

ask-yesno() {
	local question="$1" default="${2:-force}"

	local yn_text

	case "$default" in
		"force")
			yn_text="y/n"
		;;
		"true")
			yn_text="Y/n"
		;;
		"false")
			yn_text="y/N"
		;;
	esac

	sayn "\e[32;1m:? \e[0;1m$question [$yn_text]: \e[0m"

	local ans
	read -rn1 ans
	[[ $ans == "" ]] || say

	case "$ans" in
		"y"|"Y")
			echo true
			return
		;;
		
		"n"|"N")
			echo false
			return
		;;
		
		"")
			true; # NOP
		;;
		
		*)
			error "'$ans' is not a valid answer."
			ask_yesno "$question" "$default"
			return
		;;
	esac

	case "$default" in
		"true")
			echo true
			return
		;;
		"false")
			echo false
			return
		;;
		"force")
			error "Please specify your answer with a Y or an N"
			ask_yesno "$question" force
			return
		;;
	esac
}

ask() {
	local question="$1" default="$2" nullable="${3:-false}"

	sayn "\e[32;1m:?\e[0;1m $question: "
	[[ -z "$2" ]] || sayn "[$default]: "

	local ans
	read -r ans

	if [[ -n "$ans" ]]; then
		echo "$ans"
	else
		if [[ -n "$default" ]]; then
			echo "$default"
		else
			if [[ "$nullable" == true ]]; then
				return
			else
				error "Please enter the answer"
				ask "$question" "$default" "$nullable"
			fi
		fi
	fi
}

