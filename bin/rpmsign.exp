#!/usr/bin/expect -f
spawn rpm \
 --define "_gpg_name Xcalar Inc. <info@xcalar.com>"  \
 --define "_signature gpg" \
 --define "__gpg_check_password_cmd /bin/true" \
 --define "__gpg_sign_cmd %{__gpg} gpg --batch --no-verbose --no-armor --use-agent --no-secmem-warning -u '%{_gpg_name}' -sbo %{__signature_filename} %{__plaintext_filename}" \
 --addsign {*}$argv
expect -exact "Enter pass phrase: "
send -- "blank\r"
expect eof
