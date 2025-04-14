/*
*	Digital Clock: This project aims to develop a digital clock 
*    with 3 operating modes: Show the time, stopwatch and adjust the time.
*
*	Copyright (C) [2025] [Digital clock]
*	
*	Developed by:
*	-	Arturo Jim�nez Loaiza 
*	-	Gabriel Vitorino de Andrade  
*	-	Jo�o Matheus Nascimento Dias 
*	-	Manoel Pedro de Aranda Terceiro
*/

;inclusão do arquivo de configuração do microcontrolador atmega328p
.include "m328pdef.inc"

/* The interrupt vector is listed below: */
jmp INIT  ;Interruption RESET

;BUTTONS
jmp MODO  ;Interruption INT0   - button modo
jmp START ;Interruption INT1   - button start

.org 0x000E
jmp RESET ;Interruption PCINT0 - button reset

;TIME
.org OC1Aaddr
	jmp UPDATE_TIME

;Serial printer
.org 0x28
	;jmp USAR_TX

/* ******************************************* */


/* Set the varibles and registes defines to use at the code */ 
;DEFINES
.def stack		   = r5  ; Exclusive use for stack SREG config
.def flag	       = r27  ; Exclusive use to define if the nibble reg to inc is xxxx0000 or 00000xxxx 
.def temp          = r16 ; Used only with temporary data
.def mm_time	   = r22 ; Used to represent the minutes of mode 1
.def ss_time	   = r23 ; Used to represent the seconds of mode 1
.def mm_crono	   = r24 ; Used to represent the minutes of mode 2
.def ss_crono	   = r25 ; Used to represent the seocnds of mode 2
.def blink  	   = r19 ; Used to represent the what display will be blink 
.def crono 		   = r20
.def delay 		   = r21
.def modo_status   = r26 ; Used to represent the mode of the clock
.def temp2 = r28        ; Variavel temporaria
.def tx_byte = r29      ; Byte a ser transmitido pela serial
.def byte_val = r17     ; Byte a ser convertido para ASCII decimal
.def ascii_H = r18      ; Digito ASCII das dezenas
.def ascii_L = r27      ; Digito ASCII das unidades


;.SET



;.EQU
.equ full_input   = 0x00 ; If used all pins of a port will be set like input
.equ full_output  = 0xff ; If used all pins of a port will be set like output
.equ clear		  = 0x00 ; Used to reset hour or crono 
.equ display1	  = 0b00000100 ; Used to power the transistor that will set the unidade dos segundos
.equ display2	  = 0b00001000 ; Used to power the transistor that will set the dezena dos segundos
.equ display3	  = 0b00010000 ; Used to power the transistor that will set the unidade dos minutos
.equ display4	  = 0b00100000 ; Used to power the transistor that will set the dezena dos segundos
.equ displayes	  = display1 | display2 | display3 | display4 ; Use to set only the pins that realy is used
.equ B1			  = 0b00000010 ; MSB of 4 bits that is send to ci4511
.equ B2			  = 0b00000100 ; *
.equ B3			  = 0b00001000 ; *
.equ B4			  = 0b00010000 ; LSB od 4 bits that is send to ci4511
.equ buzzer		  = 0b00100000
.equ CI4511		  = B1 | B2 | B3 | B4	
.equ modo_button  = 0b00000100
.equ start_button = 0b00001000
.equ reset_button = 0b00010000
.equ buttons	  = modo_button | start_button | reset_button

.equ sum_msn	  = (1 << 4) ; Used to sium 

.equ cloclkMHz    = 16
.equ FREQ         = 16000000
.equ BAUD         = 9600


; --- Strings para a Serial ---
str_modo1: .db "[MODO 1] ", 0
str_modo2_run: .db "[MODO 2] RUN ", 0
str_modo2_start: .db "[MODO 2] START ", 0
str_modo2_zero: .db "[MODO 2] ZERO", 0
str_modo3_su: .db "[MODO 3] Ajustando a unidade dos segundos", 0
str_modo3_sd: .db "[MODO 3] Ajustando a dezena dos segundos", 0
str_modo3_mu: .db "[MODO 3] Ajustando a unidade dos minutos", 0
str_modo3_md: .db "[MODO 3] Ajustando a dezena dos minutos", 0
str_colon: .db ":", 0
str_newline: .db "\r\n", 0 ; Envia Carriage Return e Line Feed para compatibilidade

/* ******************************************* */

INIT:
	;Initial vlaues
		clr stack
		clr flag
		clr temp
		clr mm_time
		clr ss_time
		clr mm_crono
		clr ss_crono
		clr blink
		clr crono
		clr delay
		clr modo_status
		clr temp2
		clr tx_byte
		clr byte_val
		clr ascii_H
		clr ascii_L


	;Stack initialization
		ldi temp, low(RAMEND)
		mov stack, temp
		out SPL, stack
		ldi temp, high(RAMEND)
		mov stack, temp
		out SPH, stack

	;Config timer to modo1
		#define CLOCK 16.0e6 ;clock speed
		#define DELAY 0.1 ;seconds
		.equ PRESCALE = 0b100 ;/256 prescale
		.equ PRESCALE_DIV = 256
		.equ WGM = 0b0100 ;Waveform generation mode: CTC
		;you must ensure this value is between 0 and 65535
		.equ TOP = int(0.5 + ((CLOCK/PRESCALE_DIV)*DELAY))
		.if TOP > 65535
		.error "TOP is out of range"
		.endif

	;Config the ports (DDR's) - IO
		ldi temp, CI4511 | buzzer
		out DDRB, temp ; Port B is to CI4511 and buzzer

		ldi temp, displayes
		out DDRC, temp ; Port C is to transistors to select what display will be show the data. 

		ldi temp, buttons
		out DDRD, temp  ; Port D is to receiver the buttons and call the callbacks to system work very well

		ldi temp, display1
		out PORTC, temp

	;Enable especific interrupt

	; Inicializa UART
		ldi temp, HIGH((FREQ/(16*BAUD)) - 1)
		sts UBRR0H, temp
		ldi temp, LOW((FREQ/(16*BAUD)) - 1)
		sts UBRR0L, temp
		ldi temp, (1<<TXEN0)
		sts UCSR0B, temp
		ldi temp, (1<<UCSZ01)|(1<<UCSZ00)
		sts UCSR0C, temp

    ; Timer1 - 1s CTC
		ldi temp, high(TOP) ;initialize compare value (TOP)
		sts OCR1AH, temp
		ldi temp, low(TOP)
		sts OCR1AL, temp
		ldi temp, ((WGM&0b11) << WGM10) ;lower 2 bits of WGM
		; WGM&0b11 = 0b0100 & 0b0011 = 0b0000 
		sts TCCR1A, temp
		;upper 2 bits of WGM and clock select
		ldi temp, ((WGM>> 2) << WGM12)|(PRESCALE << CS10)
		sts TCCR1B, temp ;start counter

		lds	 r16, TIMSK1
		sbr r16, 1 <<OCIE1A
		sts TIMSK1, r16

    ; Interrupções externas
		ldi temp, (1<<INT0)|(1<<INT1)
		out EIMSK, temp
		ldi temp, (1<<ISC01)|(1<<ISC11)
		sts EICRA, temp
		ldi temp, (1<<PCIE2)         ; Habilita interrupção no grupo PCINT2 (PORTD)
		sts PCICR, temp
		ldi temp, (1<<PCINT20)       ; Habilita especificamente o pino PD4
		sts PCMSK2, temp

	sei

MAIN:
	cpi modo_status, 0x00
	breq MODO_ONE_MAIN

	cpi modo_status, 0x01
	breq MODO_TWO_MAIN

	cpi modo_status, 0x02
	breq MODO_THREE_MAIN

	MODO_ONE_MAIN:

		; Show the minites timer
		mov temp, mm_time  ; Load the reg that contem the minutes of the timer
		rcall SHOW_DEC_MIN ; Show the first display
		rcall SHOW_UNI_MIN ; Show the second display

		; Show the seconds timer
		mov temp, ss_time  ; Load the reg that contem the seconds of the timer
		rcall SHOW_DEC_SEG ; Show the thirt display
		rcall SHOW_UNI_SEG ; Show the fourth display

		jmp CONTINUE


	MODO_TWO_MAIN:

		; Show the minutes crono
		mov temp, mm_crono ; Load the reg that contem the minutes of the cronometro
		rcall SHOW_DEC_MIN ; Show the first display
		rcall SHOW_UNI_MIN ; Show the second display

		; Show the seconds crono
		mov temp, ss_crono ; Load the reg that contem the seconds of the cronometro
		rcall SHOW_DEC_SEG ; Show the thirt display
		rcall SHOW_UNI_SEG ; Show the fourth display

		jmp CONTINUE

	MODO_THREE_MAIN:
		ldi delay, 150 ; Set the delay to 10

		cpi blink, 0x00
		breq BLINK_FOURTH_DISPLAY ; blink the uni of the seconds display

		cpi blink, 0x01
		breq BLINK_THIRD_DISPLAY ; blink the dezena of the seconds display

		cpi blink, 0x02
		breq BLINK_SECOND_DISPLAY ; blink the uni of the minutes display

		cpi blink, 0x03
		breq BLINK_FIRST_DISPLAY ; blink the dezena of the minutes display

		BLINK_FOURTH_DISPLAY:
			mov temp, ss_time
			rcall SHOW_UNI_SEG ; Show the fourth display
			rcall DELAY_DINAMIC
			ldi temp, 0x00
			out PORTC, temp 
			rcall DELAY_DINAMIC
			rcall CONTINUE ; Show the fourth display

		BLINK_THIRD_DISPLAY:
			mov temp, ss_time
			rcall SHOW_DEC_SEG ; Show the fourth display
			rcall DELAY_DINAMIC
			ldi temp, 0x00
			out PORTC, temp 
			rcall DELAY_DINAMIC
			rcall CONTINUE ; Show the fourth display

		BLINK_SECOND_DISPLAY:
			mov temp, mm_time
			rcall SHOW_UNI_MIN ; Show the fourth display
			rcall DELAY_DINAMIC
			ldi temp, 0x00
			out PORTC, temp 
			rcall DELAY_DINAMIC
			rcall CONTINUE ; Show the fourth display
			

		BLINK_FIRST_DISPLAY:
			mov temp, mm_time
			rcall SHOW_DEC_MIN ; Show the fourth display
			rcall DELAY_DINAMIC
			ldi temp, 0x00
			out PORTC, temp 
			rcall DELAY_DINAMIC
			rcall CONTINUE ; Show the fourth display
			

	CONTINUE:
		rjmp MAIN ; Infinite loop

    

SHOW_DEC_MIN:
	push temp
	rcall GET_MOST_4_BITS ; Get the first 4 bits of the register (unit of seconds)
	swap temp
	lsl temp

	cli
	out PORTB, temp ; Send the data to the display (unit of seconds)
	sei

	ldi temp, display1

	cli
	out PORTC, temp ; Set the display to show the seconds
	sei

	pop temp
	ret


SHOW_UNI_MIN:
	push temp
	rcall GET_LAST_4_BITS ; Get the first 4 bits of the register (unit of seconds)
	lsl temp

	cli
	out PORTB, temp ; Send the data to the display (unit of seconds)
	sei

	ldi temp, display2

	cli
	out PORTC, temp ; Set the display to show the seconds
	sei

	pop temp
	ret



SHOW_DEC_SEG:
	push temp
	rcall GET_MOST_4_BITS ; Get the first 4 bits of the register (unit of seconds)
	swap temp
	lsl temp

	cli
	out PORTB, temp ; Send the data to the display (unit of seconds)
	sei

	ldi temp, display3

	cli
	out PORTC, temp ; Set the display to show the seconds
	sei

	pop temp
	ret



SHOW_UNI_SEG:
	push temp
	rcall GET_LAST_4_BITS ; Get the first 4 bits of the register (unit of seconds)
	lsl temp

	cli
	out PORTB, temp ; Send the data to the display (unit of seconds)
	sei

	ldi temp, display4

	cli
	out PORTC, temp ; Set the display to show the seconds
	sei

	pop temp
	ret

;Recebe o argumento da quantidade de delay em ms por r25 (definido por temp)
; Espera (delay) milissegundos (valor entre 1 e 255)
; Delay de aproximadamente 1ms por unidade em r25
DELAY_DINAMIC:
    push r24
    push r23

LOOP_MS:
    ldi r24, 250     ; Inner loop
    ldi r23, 32      ; Outer loop (250 * 32 ≈ 8000)

LOOP_INNER:
    dec r24
    brne LOOP_INNER

    dec r23
    brne LOOP_INNER

    dec delay
    brne LOOP_MS

    pop r23
    pop r24
    ret


FUNC_BUZZER:
	push temp

    cli ; Critical section - turn the global interruptcion off 

    ldi temp, buzzer
	OUT PORTB, temp

    ldi delay, 90 ; Await 90ms 
	rcall DELAY_DINAMIC

    in   temp, PORTB      ; Lê PORTB
    andi temp, ~(buzzer)  ; Limpa o bit do buzzer (inverte e faz AND)
    out  PORTB, temp      ; Escreve de volta


    sei ; Active the global interruptcion 
	pop temp
    ret

DEBOUNCING:
	cli 

	push stack
	in stack, SREG
	push stack

	

	ldi delay, 100
	rcall DELAY_DINAMIC ; Debouncing time


	pop stack
	out SREG, stack
	pop stack

	sei
	ret

GET_LAST_4_BITS:
	andi temp, 0b00001111 ; Get the last 4 bits of the register
	ret

GET_MOST_4_BITS:
	andi temp, 0b11110000 ; Get the most 4 bits of the register
	ret

UPDATE_TIME:
	mov temp, flag
	cpi temp, 0x00
	breq BREAK_CRONO ; If the flag is 1, go to update the crono
	rcall UPDATE_CRONO

	BREAK_CRONO:

	inc ss_time
	
	mov temp, ss_time
	rcall GET_LAST_4_BITS

	cpi temp, 0x0a ; Check if the second is 10
	breq RESET_LSN_SECOND ; If the second is less than 10, just return
	reti

	RESET_LSN_SECOND:
		andi ss_time, 0xf0
		swap ss_time
		inc ss_time
		swap ss_time

	cpi ss_time, 0x60
	breq RESET_MSN_SECOND
	reti

	RESET_MSN_SECOND:
		clr ss_time ; Reset the second to 00

	inc mm_time
	mov temp, mm_time
	rcall GET_LAST_4_BITS
	cpi temp, 0x0a 
	breq RESET_LSN_MINUTES
	RETI

	RESET_LSN_MINUTES:
		andi mm_time, 0xf0
		swap mm_time
		inc mm_time
		swap mm_time

	cpi mm_time, 0x60
	breq RESET_MSN_MINUTES
	reti

	RESET_MSN_MINUTES:
		clr mm_time ; Reset the minutes to 0
		clr ss_time ; Reset the segunds to 0

    ; Enviar Serial Modo 1: "[MODO 1] MM:SS"
    ldi ZL, low(str_modo1<<1)
    ldi ZH, high(str_modo1<<1)
    rcall USART_Transmit_String
    mov byte_val, mm_time      ; Carrega minutos
    rcall Send_Decimal_Byte   ; Envia MM
    ldi ZL, low(str_colon<<1)
    ldi ZH, high(str_colon<<1)
    rcall USART_Transmit_String ; Envia ":"
    mov byte_val, ss_time    ; Carrega segundos
    rcall Send_Decimal_Byte   ; Envia SS
    ldi ZL, low(str_newline<<1)
    ldi ZH, high(str_newline<<1)
    rcall USART_Transmit_String
	
	reti



UPDATE_CRONO:
	inc ss_crono
	
	mov temp, ss_crono
	rcall GET_LAST_4_BITS

	cpi temp, 0x0a ; Check if the second is 10
	breq RESET_LSN_SECOND_CRONO ; If the second is less than 10, just return
	ret

	RESET_LSN_SECOND_CRONO:
		andi ss_crono, 0xf0
		swap ss_crono
		inc ss_crono
		swap ss_crono

	cpi ss_crono, 0x60
	breq RESET_MSN_SECOND_CRONO
	ret

	RESET_MSN_SECOND_CRONO:
		clr ss_crono ; Reset the second to 00

	inc mm_crono
	mov temp, mm_crono
	rcall GET_LAST_4_BITS
	cpi temp, 0x0a 
	breq RESET_LSN_MINUTES_CRONO
	ret

	RESET_LSN_MINUTES_CRONO:
		andi mm_crono, 0xf0
		swap mm_crono
		inc mm_crono
		swap mm_crono

	cpi mm_crono, 0x60
	breq RESET_MSN_MINUTES_CRONO
	ret

	RESET_MSN_MINUTES_CRONO:
		clr mm_crono ; Reset the minutes to 0
		clr ss_crono ; Reset the segunds to 0
		
	ret

MODO:
    rcall DEBOUNCING

    in stack, SREG
    push stack

    rcall FUNC_BUZZER

	ldi temp, 0x00
	out PORTC, temp

    ; Incrementa o modo
    inc modo_status

    ; cpi modo_status, 0x00
    ; breq TURN_TIMER_ON

    cpi modo_status, 0x01
    breq RESET_DISPLAY_CRONO

    cpi modo_status, 0x02
    breq TURN_TIMER_OFF_BLINK

    ; Se passou de 2, reseta pra 0
    cpi modo_status, 0x03
    brlo NO_RESET_MODE

    ldi modo_status, 0x00
    rjmp TURN_TIMER_ON

TURN_TIMER_ON:
    ldi temp, ((WGM>>2)<<WGM12)|(PRESCALE<<CS10)
    sts TCCR1B, temp ; Inicia o timer
    rjmp NO_RESET_MODE

RESET_DISPLAY_CRONO:
    clr mm_crono
    clr ss_crono
    rjmp NO_RESET_MODE

TURN_TIMER_OFF_BLINK:
	clr blink
    ; Desliga o timer zerando CS12:CS10
    ldi temp, TCCR1B
    andi temp, 0b11111000 ; Zera CS12, CS11, CS10
    sts TCCR1B, temp
    rjmp NO_RESET_MODE

NO_RESET_MODE:
	ldi delay, 1
	rcall DELAY_DINAMIC
    pop stack
    out SREG, stack
    reti

START:

	push stack
	in stack, SREG
	push stack

	rcall DEBOUNCING

	push temp

	cpi modo_status, 0x00
	breq MODO_ONE_START	

	cpi modo_status, 0x01
	breq MODO_TWO_START

	cpi modo_status, 0x02
	breq MODO_THREE_START

	MODO_ONE_START:
		; to do nothing 'cause the fist modo dont have function in start
		jmp RETURN_START

	MODO_TWO_START:
		rcall FUNC_BUZZER ; Call the buzzer function to sound the buzzer
		com flag
		jmp RETURN_START


	MODO_THREE_START:
		inc blink

		cpi blink, 0x04 ; Check if the blink is 4
		breq RESET_BLINK ; If the blink is 4, go to reset the blink
		jmp RETURN_START

		RESET_BLINK:
			ldi blink, 0x00

	RETURN_START:
		pop temp
		
		pop stack
		out SREG, stack
		pop stack
		reti

RESET:

	push stack
	in stack, SREG
	push stack

	rcall DEBOUNCING

	push temp

	cpi modo_status, 0
	breq MODO_ONE_RESET

	cpi modo_status, 1
	breq MODO_TWO_RESET

	cpi modo_status, 2
	breq MODO_THREE_RESET

	MODO_ONE_RESET:
		; to do nothing 'cause the fist modo dont have function in reset
		jmp RETURN_RESET


	MODO_TWO_RESET:
		rcall FUNC_BUZZER ; Call the buzzer function to sound the buzzer
		mov temp, flag
		cpi temp, 0xff
		breq BREAK_RESET ; just reset the crono if the crono is stoped
		clr mm_crono 
		clr ss_crono

		BREAK_RESET:
		jmp RETURN_RESET
		;to do: implement the reset of cronomento

	MODO_THREE_RESET:
		cpi blink, 0x00
		breq SUM_FOUR_DISPLAY ; blink the uni of the seconds display

		cpi blink, 0x01
		breq SUM_THIRD_DISPLAY ; blink the dezena of the seconds display

		cpi blink, 0x02
		breq SUM_SECOND_DISPLAY ; blink the uni of the minutes display

		cpi blink, 0x03
		breq SUM_FIRST_DISPLAY ; blink the dezena of the minutes display

		SUM_FOUR_DISPLAY:
			mov temp, ss_time
			inc temp
			rcall GET_LAST_4_BITS ; Get the first 4 bits of the register (unit of seconds)
			cpi temp, 0x0a
			breq CLEAR_UNI_SEG 
			inc ss_time
			jmp RETURN_RESET
			CLEAR_UNI_SEG:
				andi ss_time, 0x0f ; Reset the last 4 bits of the register
				jmp RETURN_RESET

		SUM_THIRD_DISPLAY:
			mov temp, ss_time
			swap temp
			inc temp
			rcall GET_LAST_4_BITS ; Get the first 4 bits of the register (unit of seconds)
			cpi temp, 0x0a
			breq CLEAR_DEC_SEG 
			swap ss_time
			inc ss_time
			swap ss_time
			jmp RETURN_RESET
			CLEAR_DEC_SEG:
				andi ss_time, 0xf0 ; Reset the last 4 bits of the register
				jmp RETURN_RESET

		SUM_SECOND_DISPLAY:
			mov temp, mm_time
			inc temp
			rcall GET_LAST_4_BITS ; Get the first 4 bits of the register (unit of seconds)
			cpi temp, 0x0a
			breq CLEAR_UNI_MIN
			inc mm_time
			jmp RETURN_RESET
			CLEAR_UNI_MIN:
				andi mm_time, 0x0f ; Reset the last 4 bits of the register
				jmp RETURN_RESET

		SUM_FIRST_DISPLAY:
			mov temp, mm_time
			swap temp
			inc temp
			rcall GET_LAST_4_BITS ; Get the first 4 bits of the register (unit of seconds)
			cpi temp, 0x0a
			breq CLEAR_DEC_MIN
			swap mm_time
			inc mm_time
			swap mm_time
			jmp RETURN_RESET
			CLEAR_DEC_MIN:
				andi mm_time, 0xf0 ; Reset the last 4 bits of the register
				jmp RETURN_RESET

	RETURN_RESET:
		pop temp

		pop stack		
		out SREG, stack
		pop stack
		reti

; --- USART_Transmit ---
; Envia um byte pela serial. Espera o buffer estar livre.
; Entrada: tx_byte (r19) contém o byte a ser enviado
USART_Transmit:
    push temp          ; Salva r16
tx_wait_loop:
    lds temp, UCSR0A   ; Lê o status do USART
    sbrs temp, UDRE0   ; Pula a próxima instrução se o bit UDRE0 (Data Register Empty) estiver setado (1)
    rjmp tx_wait_loop   ; Se não estiver vazio (UDRE0=0), espera
    sts UDR0, tx_byte   ; Coloca o byte no buffer de transmissão (envia)
    pop temp           ; Restaura r16
    ret

; --- USART_Transmit_String ---
; Envia uma string (terminada em NULL) localizada na memória de programa (Flash).
; Entrada: Z (r31:r30) aponta para o início da string na memória de programa.
; Usa: Z, tx_byte (r19), temp (r16)
USART_Transmit_String:
    push temp          ; Salva r16
    push r30
    push r31
str_loop:
    lpm tx_byte, Z+     ; Carrega byte da memória de programa no tx_byte e incrementa Z
    tst tx_byte         ; Verifica se o byte carregado é zero (NULL terminator)
    breq str_end        ; Se for zero, fim da string
    rcall USART_Transmit ; Envia o byte
    rjmp str_loop       ; Próximo caractere
str_end:
    pop r31
    pop r30
    pop temp           ; Restaura r16
    ret

; --- Send_Decimal_Byte ---
; Converte um byte (0-99) em dois caracteres ASCII decimais e os envia pela serial.
; Entrada: byte_val (r20) contém o valor (0-99)
; Saída: Envia os dois caracteres ASCII pela serial
; Usa: byte_val (r20), ascii_H (r21), ascii_L (r22), tx_byte (r19), temp (r16)
Send_Decimal_Byte:
    push temp           ; Salva r16
    push r17           ; Salva r17
    push r20           ; Salva byte_val original se precisar depois

    mov temp, byte_val  ; Copia valor para temp (usado por div10)
    rcall div10          ; Chama sub-rotina de divisão por 10
                         ; Resultado: temp=quociente (dezena), temp2=resto (unidade)

    mov ascii_H, temp   ; Guarda a dezena
    mov ascii_L, temp2   ; Guarda a unidade

    ; Converte dezena para ASCII ('0' = 0x30)
    subi ascii_H, -0x30  ; Adiciona 0x30
    mov tx_byte, ascii_H ; Prepara para transmitir
    rcall USART_Transmit ; Envia dígito das dezenas

    ; Converte unidade para ASCII
    subi ascii_L, -0x30  ; Adiciona 0x30
    mov tx_byte, ascii_L ; Prepara para transmitir
    rcall USART_Transmit ; Envia dígito das unidades

    pop r20
    pop r17
    pop temp
    ret

; --- div10 ---
; Sub-rotina simples para dividir por 10 
; Entrada: temp = valor (0-99)
; Saída: temp = quociente (Dezena), temp2 = resto (Unidade)
; Usa: temp, temp2
div10:
    clr temp2           ; temp2 será o quociente (dezenas)
div10_loop:
    cpi temp, 10       ; Compara com 10
    brlo div10_end      ; Se for menor, acabou
    subi temp, 10      ; Subtrai 10
    inc temp2           ; Incrementa quociente
    rjmp div10_loop
div10_end:
    ; No fim: temp tem o resto (unidade), temp2 tem o quociente (dezena)
    ; Troca para retornar como especificado (temp=quociente, temp2=resto)
    push temp
    mov temp, temp2
    pop temp2
    ret
