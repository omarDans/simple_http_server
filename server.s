.intel_syntax noprefix
.global _start
.type main, @function
.type parseRequest, @function
.type getPostData, @function
.type getContentLength, @function
.type atoi, @function
.type extractFile, @function
.type findStr, @function
.type getLength, @function

.section .data
	msg: .ascii "HTTP/1.0 200 OK\r\n\r\n\0"
	post: .ascii "POST\0"
	content_length: .ascii "Content-Length: \0"

.section .text

_start:
	# stack frame initialization
	push rbp
	mov rbp, rsp
	sub rsp, 0x10 # sockaddr_in memory

	# populate sockaddr_in structure
	mov word ptr [rsp+0x00], 2 # AF_INET
	mov word ptr [rsp+0x2], 0x5000 # PORT 80
	mov dword ptr [rsp+0x4], 0x00000000 # HOST 0.0.0.0

	# create socket
	mov rdx, 0
	mov rsi, 1
	mov rdi, 2
	mov rax, 41
	syscall
	mov r9, rax # save fd for later

	# call bind
	mov dx, 16
	mov rsi, rsp
	mov di, ax
	mov ax, 49
	syscall

	# listen for connections
	mov rsi, 0
	mov rax, 50
	syscall
.L_loop_main:	
	# accept connections
	xor rdx, rdx
	xor rsi, rsi
	mov rdi, r9
	mov rax, 43
	syscall
	mov r10, rax # save fd

	# Create child proccess (fork)
	mov rax, 57
	syscall
	
	# Check if we are in child process
	cmp rax, 0
	jne .L_out_main

### CHILD PROCESS START ###
	push rbp
	mov rbp, rsp
	sub rsp, 0x500

	# close socket fd
	mov rdi, r9
	mov rax, 3
	syscall

	# read client
	mov rdx, 0x200
	lea rsi, [rsp]
	mov rdi, r10
	mov rax, 0
	syscall

	# call parse_request
	mov rdi, rsi
	lea rsi, [rsp+0x200] # PostData buffer
	lea rdx, [rsp+0x400] # extractFile buffer
	call parseRequest

	# check the type of request (GET/POST)
	cmp rbx, 0
	jne .L_post_main

### GET ###

	# open readed file
	mov rsi, 0 # O_RDONLY
	mov rdi, rax
	mov rax, 2 # open()
	syscall

	# read content of the file
	mov rdx, 0x200
	lea rsi, [rsp]
	mov rdi, rax
	mov rax, 0 # read()
	syscall

	# terminate buf with zero
	lea rsi, [rsp+rax]
	push rsp # save start buffer address
	push rax # save readed bytes for later
	mov bl, 0
	mov [rsi], bl

	# close file
	mov rax, 3 # close()
	syscall

	# static response
	mov rdx, 19
	lea rsi, [msg]
	mov rdi, r10
	mov rax, 1 # write()
	syscall

	# dynamic response
	pop rdx # readed bytes
	pop rsi # readed content buffer
	mov rdi, r10
	mov rax, 1
	syscall
	
	jmp .L_exit_child
.L_post_main:
	# open file
	push rcx # save post data content ( for some reason after open(), rcx gets changed )
	mov rdi, rax
	mov rsi, 64 # O_CREAT
	or rsi, 1 # O_WRONLY | O_CREAT
	mov rdx, 0x1ff # 0x1ff == 0777 <- this is octal
	mov rax, 2 # open()
	syscall

	# write content
	mov rdx, rbx # POST data length
	pop rsi # POST data content
	mov rdi, rax # file descriptor
	mov rax, 1
	syscall

	# close fd
	mov rax, 3
	syscall

	# write 200 OK
	mov rdx, 19
	lea rsi, [msg]
	mov rdi, r10 # accpeted file descriptor
	mov rax, 1
	syscall

.L_exit_child:
	# Exit the child process
	add rsp, 0x500
	mov rdi, 0
	mov rax, 60
	syscall

### CHILD PROCESS END ###

.L_out_main:
	# close fd
	mov rdi, r10
	mov rax, 3
	syscall

	# jump back to accept connections
	jmp .L_loop_main

	# exit
	mov rdi, 0
	mov rax, 60
	syscall


### PARSE REQUEST ####
# ParseRequest will check the type of the request (GET/POST).L_ If the request is type GET it will get the requested file and return. If the request is type POST it will get the requested file, the 'Content-Length' value and the POST data
parseRequest:
	push rbp
	mov rbp, rsp

	push r10 # save the file descriptor for the connection
	push rsi # save address of the postData buffer
	push rdx # save address of the extractfile buffer

	lea rsi, [post]
	call findStr
	cmp rax, 0 # If we don't find the 'POST' string we assume is a GET request (yeah, idc)
	jne .L_post_parseRequest

	# GET Request
	mov rsi, 4
	pop rdx
	call extractFile

	xor rbx, rbx
	pop rsi
	pop r10
	pop rbp
	ret
.L_post_parseRequest: # POST Request
	mov rsi, 5
	pop rdx # restore extractFile buffer
	pop rcx # restore getPostData buffer
	call extractFile
	push rax

	call getContentLength
	push rax
	mov rsi, rax
	mov rdx, rcx

	call getPostData
	mov rcx, rax # POST data content
	pop rbx # POST data length
	pop rax # extracted File
	pop r10 # socket fd
	pop rbp
	ret

### GetPostData ###
# This function receives the request's buffer, the size of the post data and a buffer as
# arguments and returns the post data from the request in the given buffer.
getPostData:
	push rbp
	mov rbp, rsp

.L_first_getPostData:
	mov cl, byte ptr [rdi]
	cmp cl, '\r'
	jne .L_continue_getPostData
	inc rdi
	mov cl, byte ptr [rdi]
	cmp cl, '\n'
	jne .L_continue_getPostData
	inc rdi
	mov cl, byte ptr [rdi]
	cmp cl, '\r'
	jne .L_continue_getPostData
	inc rdi
	mov cl, byte ptr [rdi]
	cmp cl, '\n'
	jne .L_continue_getPostData
	inc rdi
	xor rbx, rbx
.L_begin_getPostData:
	cmp rbx, rsi # should copy one extra byte, we use this like a null byte terminator
	je .L_end_getPostData
	mov cl, byte ptr [rdi+rbx]
	mov [rdx+rbx], cl
	inc rbx
	jmp .L_begin_getPostData
.L_continue_getPostData:
	inc rdi
	jmp .L_first_getPostData
.L_end_getPostData:
	mov rax, rdx
	pop rbp
	ret

### GetContentLength ###
# This function gets the value of the 'Content-Length' header and then parses it to int
# by calling to custom atoi (ascii to int)
# it receives the request's buffer (rdi) as an argument and returns the value of the
# 'Content-Length' as int
getContentLength:
	push rbp
	mov rbp, rsp
	push rcx # save getPostData buffer
	sub rsp, 0x20

	lea rsi, [content_length]
	call findStr
	cmp rax, 0
	ja .L_ok_getContentLength

	pop rbp
	ret
.L_ok_getContentLength:
	add rdi, rax
	xor rbx, rbx
.L_begin_getContentLength:
	mov cl, byte ptr [rdi]
	cmp cl, 0x30
	jb .L_finish_getContentLength
	cmp cl, 0x39
	ja .L_finish_getContentLength

	mov byte ptr [rsp+rbx], cl
	inc rdi
	inc rbx
	jmp .L_begin_getContentLength
.L_finish_getContentLength:
	mov byte ptr [rsp+rbx], 0 # terminate string with null byte
	lea rsi, [rsp]

	push rdi # save request's buffer pointer
	mov rdi, rsi
	call atoi
	pop rdi

	add rsp, 0x20
	pop rcx # restore getPostData buffer
	pop rbp
	ret
	

# Ascii to int function ( a little help from GPT ngl )
# I was implementing a different logic, this is a lot more efficient
atoi:
	push rbp
	mov rbp, rsp

	xor rax, rax
	xor rcx, rcx

.L_next_char_atoi:
	mov cl, byte ptr [rdi]
	cmp cl, 0
	je .L_done_atoi

	sub cl, 0x30
	imul rax, rax, 10
	add rax, rcx
	inc rdi
	jmp .L_next_char_atoi

.L_done_atoi:
	pop rbp
	ret

### ExtractFile ###
# This function takes the request buffer (rdi), the amount of bytes to ignore (GET/POST)
# (rsi) and a buffer (rdx).
# Gets the wanted file from the request and saves it in the given buffer and returns it.
extractFile:
	push rbp
	mov rbp, rsp
	push rcx # save pointer to getPostData buffer

	xor rax, rax
	add rdi, rsi # ignore request's type (GET/POST)
.L_begin_extractFile:
	mov cl, byte ptr [rdi+rax]
	cmp cl, 0x20 # hex value for whitespace
	je .L_finish_extractFile
	mov byte ptr [rdx+rax], cl
	inc rax
	jmp .L_begin_extractFile
.L_finish_extractFile:
	mov rax, rdx
	pop rcx
	pop rbp
	ret

### FindStr ###
# Takes a buffer with data (rdi) and another buffer with the substring to find (rsi)
# This function finds a substring in a buffer, if it has been found, returns the index of that string else, returns 0
findStr:
	push rbp
	mov rbp, rsp
	# get length of rsi
	push rdi
	mov rdi, rsi
	call getLength
	pop rdi
	mov rbx, rax # length for rsi (POST/GET) buffer
	# get length of rdi
	call getLength
	mov r10, rax # length for rdi buffer
	xor rax, rax # substring index
	xor r9, r9 # buffer index
	jmp .L_first_findStr
.L_loop_findStr:
	mov dl, [rdi+r9]
	mov cl, [rsi+rax]
	cmp dl, cl
	jne .L_n_eq_findStr
	inc rax
	inc r9
.L_first_findStr: # loop start
	cmp rax, rbx
	je .L_eq_findStr
	cmp r9, r10 # end of buffer?
	ja .L_finish_findStr
	jmp .L_loop_findStr
.L_eq_findStr: # is equal
	mov rax, r9
	pop rbp
	ret
.L_n_eq_findStr: # is not equal
	inc r9
	xor rax, rax
	jmp .L_loop_findStr
.L_finish_findStr: # not found
	xor rax, rax
	pop rbp
	ret

### GetLength ###
# classic getlength function from string.h header
# counts bytes until nullbyte is found
getLength:
	push rbp
	mov rbp, rsp
	xor rax, rax
.L_begin_getLength:
	mov dl, byte ptr [rdi+rax]
	cmp dl, 0
	je .L_finish_getLength
	inc rax
	jmp .L_begin_getLength
.L_finish_getLength:
	pop rbp
	ret
