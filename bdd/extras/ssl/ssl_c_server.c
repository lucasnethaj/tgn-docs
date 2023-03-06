#include <errno.h>
#include <unistd.h>
#include <malloc.h>
#include <string.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <resolv.h>
#include "openssl/ssl.h"
#include "openssl/err.h"
#define FAIL -1

int listener_size = 10;
int verbose=0;
// Create the SSL socket and intialize the socket address structure
int OpenListener(int port)
{
    int opt = 1;
    int sd;
    struct sockaddr_in addr;
    sd = socket(PF_INET, SOCK_STREAM, 0);
    bzero(&addr, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = INADDR_ANY;
    if (bind(sd, (struct sockaddr *)&addr, sizeof(addr)) != 0)
    {
        perror("can't bind port");
        abort();
    }
    if (listen(sd, listener_size) != 0)
    {
        perror("Can't configure listening port");
        abort();
    }
    return sd;
}

SSL_CTX *InitServerCTX(void)
{
 //   SSL_METHOD *method;
    SSL_CTX *ctx;
    OpenSSL_add_all_algorithms();     /* load & register all cryptos, etc. */
    SSL_load_error_strings();         /* load all error messages */
    const SSL_METHOD* method = TLS_server_method(); /* create new server-method instance */
    ctx = SSL_CTX_new(method);        /* create new context from method */
    if (ctx == NULL)
    {
        ERR_print_errors_fp(stderr);
        abort();
    }
    return ctx;
}

void LoadCertificates(SSL_CTX *ctx, char *CertFile, char *KeyFile)
{
    /* set the local certificate from CertFile */
    if (SSL_CTX_use_certificate_file(ctx, CertFile, SSL_FILETYPE_PEM) <= 0)
    {
        ERR_print_errors_fp(stderr);
        abort();
    }
    /* set the private key from KeyFile (may be the same as CertFile) */
    if (SSL_CTX_use_PrivateKey_file(ctx, KeyFile, SSL_FILETYPE_PEM) <= 0)
    {
        ERR_print_errors_fp(stderr);
        abort();
    }
    /* verify private key */
    if (!SSL_CTX_check_private_key(ctx))
    {
        fprintf(stderr, "Private key does not match the public certificate\n");
        abort();
    }
}

void ShowCerts(SSL *ssl)
{
    X509 *cert;
    char *line;
    cert = SSL_get_peer_certificate(ssl); /* Get certificates (if available) */
    if (cert != NULL)
    {
        printf("Server certificates:\n");
        line = X509_NAME_oneline(X509_get_subject_name(cert), 0, 0);
        printf("Subject: %s\n", line);
        free(line);
        line = X509_NAME_oneline(X509_get_issuer_name(cert), 0, 0);
        printf("Issuer: %s\n", line);
        free(line);
        X509_free(cert);
    }
    else
        printf("No certificates.\n");
}

int Servlet(SSL *ssl) /* Serve the connection -- threadable */
{
    char buf[1024] = {0};
    int sd, bytes;
    if (SSL_accept(ssl) == FAIL)
    { /* do SSL-protocol accept */
        ERR_print_errors_fp(stderr);
    }
    else
    {
        ShowCerts(ssl);                          /* get any certificates */
        bytes = SSL_read(ssl, buf, sizeof(buf)); /* get request */
        buf[bytes] = '\0';
        printf("Client msg: \"%s\"\n", buf);
        if (bytes > 0)
        {
            SSL_write(ssl, buf, strlen(buf)); /* send reply */
        }
        else
        {
            ERR_print_errors_fp(stderr);
        }
    }
    SSL_shutdown(ssl);

    sd = SSL_get_fd(ssl); /* get socket connection */
    // close(sd);            /* close connection */
    SSL_free(ssl); /* release SSL state */
    printf("buf=%s\n", buf);
    return strcmp(buf, "EOC");
}

int main(int count, char *Argc[])
{
    struct sockaddr_in address;
    int addrlen = sizeof(address);
    SSL_CTX *ctx;
    int server;
    char *portnum;
	char *cert;
    if (count < 2)
    {
        printf("Usage: %s <portnum> [<cert-file>] [verbose]\n", Argc[0]);
        exit(0);
    }
    // Initialize the SSL library
    SSL_library_init();
    portnum = Argc[1];
    ctx = InitServerCTX(); 
    if (count >= 3)
    {
		cert =Argc[2];
    }
	else if (count >= 4) {
		verbose = 1;
	}
    else
    {
        /* initialize SSL */
		cert="mycert.pem";
    }
    
    LoadCertificates(ctx, cert, cert); /* load certs */
	server = OpenListener(atoi(portnum)); /* create server socket */
    int tr;
    if (listen(server, listener_size) < 0)
    {
        perror("listen");
        return 1;
    }
    printf("port %s cert %s\n", portnum, cert); 
    int ret = 1;
    while (ret)
    {
        struct sockaddr_in addr;
        socklen_t len = sizeof(addr);
        SSL *ssl;
        int client = accept(server, (struct sockaddr *)&addr, &len); /* accept connection as usual */
        if (verbose) printf("Connection: %s:%d\n", inet_ntoa(addr.sin_addr), ntohs(addr.sin_port));
        ssl = SSL_new(ctx);      /* get new SSL state with context */
        SSL_set_fd(ssl, client); /* set connection socket to SSL state */
        ret = Servlet(ssl);      /* service connection */
        if (verbose) printf("ret=%d\n", ret);
    }
    printf("Shutdown!");
    // SSL_shutdown(ssl);
    //	shutdown(server);
    SSL_CTX_free(ctx); /* release context */
    shutdown(server, SHUT_RDWR);
    close(server); /* close server socket */
    return 0;
}
