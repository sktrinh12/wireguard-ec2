#### Client

To just test interactively in terminal, first generate client keys:
```
CIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo $CLIENT_PRIVATE_KEY | wg pubkey)
```

Then pass to terraform argument: 

```
terraform apply -auto-approve -var="client_public_key=${CLIENT_PUBLIC_KEY}"
```
