source /opt/turboarch/common.sh

fatal-error() {
	error "fatal: $*"
	info "Failed to set up the system. Your system will reboot back to Windows."
	press-any-key
	remove-installer-efi-entry
	exit 2
}

remove-installer-efi-entry() {
	efibootmgr -B --label "Install TurboArch"
	return $?
}

press-any-key() {
	sayn "\e[0;1mPress any key to continue...\e[0m"
	read -rn 1
}

ask-password() {
	local username="$1"

	info "Setting a new password for '$username'"
	warning "Your input won't be shown on the screen. Just type the password and press enter."
	
	read -rsp "New password for '$username': " password
	say
	read -rsp "Repeat the password for '$username': " repeat_password
	say

	if [[ "$password" != "$repeat_password" ]]; then
		error "Passwords don't match. Try again."
		ask-password "$username"
		return
	fi

	echo "$password"
}

set-password() {
	local username="$1" password="$2"

	passwd "$username" &> /dev/null <<< "$(echo -ne "$password\n$password\n")"
	return $?
}

get-device-by-partuuid() {
	local partuuid="$1"

	blkid --match-token "PARTUUID=$partuuid" -o device
}

service-exists() {
	local service="$1"

	if [[ "$(systemctl list-unit-files -q "$service" | wc -l)" == "1" ]]; then
		echo true
	else
		echo false
	fi
}
