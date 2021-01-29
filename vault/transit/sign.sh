#!/bin/bash


# Initialize this key. Done once, nobody ever sees the private key unless you specify
# you want it at init time. The key will be marked as tainted having been exported out'
# of Vault.

# vault write -f transit/keys/test-license type=rsa-4096
# Success! Data written to: transit/keys/test-license

# Return signature of whatever is passed into stdin
signLicense() {
    vault write -field=signature transit/sign/test-license input="$(echo "$1" | base64)"
    #Sample output:
    #Key          Value
    #---          -----
    #signature    vault:v1:AAufE+u03LXywCIZwzzN4lRr4FKuNJFp1g4/5Tg6v4JXGEI/J86dZ3RIelNaFjGKDYAm0T1tJzJ9SABxvongXUX3jJY2jH9+QetTNQFcgAK8fldbAAZWHuPGv8aZ5p7guCUU8FE6E6TDBGDw1yLCPPY5hBmjUJu5/R3u90rzs3hO/y+0QDQVfAOPFPKQgGN4MVbScK5B9MEYVbilZ1Vj/RvG8IIPWgkvLSeBvof5mp/kh6Jb4gDYEWr9iESv5abCQWBaOjL8hBD1HCmUKR8Tc/Da/zz5PR9x+kHNu+PpYa8/vnut2No4IZ/KOTNF1XVEzYhNKuG8GpeavypISLqAE5DQThn5ierekJcTSkQ1D5KTEHg1p/FSZ8Av+GJ/ZmTWqNGJ8fvSwptsCu4/kPnhadZ9ZDIpipzpmyJQS0gvDM6KCekbovwjKFGeuBl6vhyVrOttpFDLDB1PAKBEoJ8D83Misvpaaod5Luep+3bAjPcyTkjUd6VGzkXk5hJgeaRPBIywq5TkT7YADJErHTLP5IxRErPQPNaUnXNYb2jlOND7yVGR5m+u1WUzAZfxb1ie65aJymGvQwEaTvCaZkMHoXcS/yulsE+vpTnwTSEOx6kByUx2UBh/fS6xk0OjijlloyqGCzTgO0Nwm4TwSKlJxx2vMvMrh5yvY2GWlpz8+yU=
}

# Check what is passed into $2 verifies with the license in $1
verifyLicense() {
    echo >&2 -n "Verifying: $2 ..."
    result=$(vault write -field=valid transit/verify/test-license signature="$1" input="$(echo "$2" | base64)")
    echo " $result"
    echo >&2 ""
    [[ $result == true ]]
}


license="NumNodes=10 MaxUsers=20"

test_sig=$(signLicense "$license")

echo >&2 "Generated license for '$license'"

echo >&2 "Signature: ${test_sig:0:20}..."

verifyLicense $test_sig "NumNodes=10 MaxUsers=10"

verifyLicense $test_sig "NumNodes=10 MaxUsers=20"

verifyLicense $test_sig "NumNodes=20 MaxUsers=10"
