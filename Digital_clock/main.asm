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
.def flag	       = r6  ; Exclusive use to define if the nibble reg to inc is xxxx0000 or 00000xxxx 
.def temp          = r16 ; Used only with temporary data
.def display_hour  = r17 ; Exclusive use for modes 1 and 3 (show and adjust time for display)
.def display_crono = r18 ; Exclusive use for mode 2 (show local cronometro)
.def mm_time	   = r22 ; Used to represent the minutes of mode 1
.def ss_time	   = r23 ; Used to represent the seconds of mode 1
.def mm_crono	   = r24 ; Used to represent the minutes of mode 2
.def ss_crono	   = r25 ; Used to represent the seocnds of mode 2
.def hour  		   = r19
.def crono 		   = r20
.def delay 		   = r21
.def modo_status   = r26 ; Used to represent the mode of the clock

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


;Storages
show_display: .db display1, display2, display3, display4

/* ******************************************* */

/* Start program and routine and interrupcion implementation */
.org 0x34

INIT:
	;Initial vlaues
		clr temp 
		clr display_hour 
		clr display_crono 
		clr stack 
		clr flag
		clr mm_time 
		clr ss_time
		clr mm_crono
		clr ss_crono
		clr hour 
		clr crono 
		clr delay
		clr modo_status


	;Stack initialization
		ldi temp, low(RAMEND)
		mov stack, temp
		out SPL, stack
		ldi temp, high(RAMEND)
		mov stack, temp
		out SPH, stack

	;Config timer to modo1
		#define CLOCK 16.0e6 ;clock speed
		#define DELAY 0.0001 ;seconds
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
	cpi modo_status, 0
	breq MODO_ONE_MAIN

	cpi modo_status, 1
	breq MODO_TWO_MAIN

	cpi modo_status, 2
	breq MODO_THREE_MAIN

	MODO_ONE_MAIN:
		SHOW_DEC_MIN:
			mov temp, mm_time
			rcall GET_MOST_4_BITS ; Get the first 4 bits of the register (unit of seconds)
			swap temp
			lsl temp

			out PORTB, temp ; Send the data to the display (unit of seconds)

			ldi temp, display1
			out PORTC, temp ; Set the display to show the seconds
			;jmp CONTINUE


		SHOW_UNI_MIN:
			mov temp, mm_time
			rcall GET_LAST_4_BITS ; Get the first 4 bits of the register (unit of seconds)
			lsl temp

			out PORTB, temp ; Send the data to the display (unit of seconds)

			ldi temp, display2
			out PORTC, temp ; Set the display to show the seconds



		SHOW_DEC_SEG:
			mov temp, ss_time
			rcall GET_MOST_4_BITS ; Get the first 4 bits of the register (unit of seconds)
			swap temp
			lsl temp

			out PORTB, temp ; Send the data to the display (unit of seconds)

			ldi temp, display3
			out PORTC, temp ; Set the display to show the seconds
	


		SHOW_UNI_SEG:
			mov temp, ss_time
			rcall GET_LAST_4_BITS ; Get the first 4 bits of the register (unit of seconds)
			lsl temp

			out PORTB, temp ; Send the data to the display (unit of seconds)

			ldi temp, display4
			out PORTC, temp ; Set the display to show the seconds
			jmp CONTINUE



	MODO_TWO_MAIN:

	MODO_THREE_MAIN:

	CONTINUE:
		rjmp MAIN ; Infinite loop

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
    cli ; Critical section - turn the global interruptcion off 

    ldi temp, buzzer
	OUT PORTB, temp

    ldi delay, 90      ; Await 90ms 
	rcall DELAY_DINAMIC

    in   temp, PORTB           ; Lê PORTB
    andi temp, ~(buzzer)  ; Limpa o bit do buzzer (inverte e faz AND)
    out  PORTB, temp           ; Escreve de volta


    sei ; Active the global interruptcion 
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
		
	reti



UPDATE_CRONO:
	inc ss_crono
	
	mov temp, ss_crono
	rcall GET_LAST_4_BITS

	cpi temp, 0x0a ; Check if the second is 10
	breq RESET_LSN_SECOND ; If the second is less than 10, just return
	reti

	RESET_LSN_SECOND:
		andi ss_crono, 0xf0
		swap ss_crono
		inc ss_crono
		swap ss_crono

	cpi ss_crono, 0x60
	breq RESET_MSN_SECOND
	reti

	RESET_MSN_SECOND:
		clr ss_crono ; Reset the second to 00

	inc mm_crono
	mov temp, mm_crono
	rcall GET_LAST_4_BITS
	cpi temp, 0x0a 
	breq RESET_LSN_MINUTES
	RETI

	RESET_LSN_MINUTES:
		andi mm_crono, 0xf0
		swap mm_crono
		inc mm_crono
		swap mm_crono

	cpi mm_crono, 0x60
	breq RESET_MSN_MINUTES
	reti

	RESET_MSN_MINUTES:
		clr mm_crono ; Reset the minutes to 0
		clr ss_crono ; Reset the segunds to 0
		
	reti

; Soma 1 em um nibble especifico de um reg que é passado por temp
ADJUST_NIBBLE_TIME:
	ldi r31, 0x01
	cp flag, r31 ; Check if the nibble is the last 4 bits
	breq MOST_NIBBLE ; If the nibble is the last 4 bits, go to reset the last 4 bits of the second
	inc temp ; Incress the nibble of the register
	cpi temp, 0x0a ; Check if the nibble is 10
	breq CLEAN_LAST_LSN_NIBBLE ; If the nibble is 10, go to reset the last 4 bits of the second
	ret
	CLEAN_LAST_LSN_NIBBLE:
		andi temp, 0b11110000 ; Reset the last 4 bits of the register
		ret

	MOST_NIBBLE:
		ldi r31, sum_msn
		add temp, r31 ; Add 1 to the most significant nibble
		cpi temp, 0x50 ; Check if the nibble is 10
		breq CLEAN_MOST_MSN_NIBBLE ; If the nibble is 10, go to reset the last 4 bits of the second
		ret
		CLEAN_MOST_MSN_NIBBLE:
			andi temp, 0b00001111 ; Reset the most significant nibble of the register
			ret	

MODO:
	push stack
	in stack, SREG
	push stack
	
	rcall FUNC_BUZZER ; Even that the state is chenage the buzzer is play
    
	inc modo_status
	cpi modo_status, 0x03
	brne NO_RESET_MODE
	clr modo_status
		
	NO_RESET_MODE:
	
	pop stack
	out SREG, stack
	pop stack

	reti

START:
	push stack
	in stack, SREG
	push stack

	cpi modo_status, 0x00
	breq MODO_ONE_START	

	cpi modo_status, 0x01
	breq MODO_TWO_START

	cpi modo_status, 0x02
	breq MODO_THREE_START

	MODO_ONE_START:
		ldi temp, 0x1
		lsl temp
		out PORTB, temp
		jmp RETURN_START

	MODO_TWO_START:
		ldi temp, 0x2
		lsl temp
		out PORTB, temp
		jmp RETURN_START


	MODO_THREE_START:
		ldi temp, 0x3
		lsl temp
		out PORTB, temp
		jmp RETURN_START
		

	RETURN_START:
		pop stack
		out SREG, stack
		pop stack
		reti

RESET:
	push stack
	in stack, SREG
	push stack

	cpi modo_status, 0
	breq MODO_ONE_RESET

	cpi modo_status, 1
	breq MODO_TWO_RESET

	cpi modo_status, 2
	breq MODO_THREE_RESET

	MODO_ONE_RESET:
		ldi temp, 0xa
		lsl temp
		out PORTB, temp
		jmp RETURN_RESET
		;to do: to do nothing

	MODO_TWO_RESET:
		ldi temp, 0xb
		lsl temp
		out PORTB, temp
		jmp RETURN_RESET
		;to do: implement the reset of cronomento

	MODO_THREE_RESET:
		ldi temp, 0xc
		lsl temp
		out PORTB, temp
		jmp RETURN_RESET
		;to do: implement the incress of hour (config)

	RETURN_RESET:
		pop stack		
		out SREG, stack
		pop stack
		reti
