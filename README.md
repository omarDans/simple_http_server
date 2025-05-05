# Simple_Http_Server
Im currently working in the website [pwncollege](pwncollege.com) and one of the exercise is making a custom 
http server using assembly. 

It was really fun to make and i learned a lot so i decided to add a lot of comments to make it as readable as posible and i hope i can help others starting too!

### Functionality
As the name says, the functionality of this webserver is very simple but it catched ( i think ) all the important concepts if you are looking to learn assembly:

- "_start:" is the entry point for the binary and has all the core code.
-  "parseRequest" is the second more important function, this function is going to check the type of the request (GET/POST) and return one or more elements depending on the type:
		- (GET): For this type of request, parseRequest is going to extract the path of the file that is being requested and return it. ( then _start: is going to read the content of the file and write it to the socket )
		- (POST): For this type of request, parseRequest is going to extract the path of the file that is being requested, get the value of the "Content-Length" header and save the post data. ( then _start: is going to write the post data content into the file specified in the request )
- There is also some functions as "utility" ( findStr, getLength...etc ). All this functions has a explanatory comment.
- Also, im not using the standard library so you can compile with: `gcc -nostdlib -o server server.s`

*I must say that i'm ignoring (sometimes) the ABI conventions but, yeah wharever*
