1.  Get the port at which the langfuse web server is running (typically 3000)

```bash
kubectl get services -n langfuse | grep 'langfuse-web'
```

2. Set up a local port forward to the langfuse web server

```bash
kubectl port-forward -n langfuse svc/langfuse-web 3000:3000
```

3. Visit the Langfuse web interface at `http://localhost:3000`

4. Sign up with your email address, and then follow the instructions to create
   an organization, project and API key

5. Note down your secret key and public key

6. Set up langfuse connection on Relvy. Provide the secret and public key from
   above when prompted.

```bash
./install.sh --connect_langfuse
```
