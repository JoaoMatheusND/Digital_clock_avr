/*
*	Digital Clock: This project aims to develop a digital clock 
*    with 3 operating modes: Show the time, stopwatch and adjust the time.
*
*	Copyright (C) [2025] [Digital clock]
*	
*	Developed by:
*	-	Arturo Jiménez Loaiza 
*	-	Gabriel Vitorino de Andrade  
*	-	João Matheus Nascimento Dias 
*	-	Manoel Pedro de Aranda Terceiro
*/

/* The interrupt vector is listed below: */
jmp INIT  ;Interruption RESET

;BUTTONS
jmp MODO  ;Interruption INT0   - button modo
jmp START ;Interruption INT1   - button start
jmp RESET ;Interruption PCINT0 - button reset

;TIME
.org OC1Aaddr
	jmp UPDATE_HOUR

;Serial printer
.org 0x28
	;jmp USAR_TX

/* ******************************************* */


/* Set the varibles and registes defines to use at the code */ 
;DEFINES
.def temp          = r16 ; Used only with temporary data
.def display_hour  = r17 ; Exclusive use for modes 1 and 3 (show and adjust time for display)
.def display_crono = r18 ; Exclusive use for mode 2 (show local cronometro)

;.SET
.set hour  = r19
.set crono = r20
.set delay = r21

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
.equ CI4511		  = B1 | B2 | B3 | B4	
.equ buzzer		  = 0b00100000
.equ modo_button  = 0b00000100
.equ start_button = 0b00001000
.equ reset_button = 0b00010000
.equ buttons	  = modo_button | start_button | reset_button

.equ cloclkMHz = 16


;Storages
show_display: .db display1, display2, display3, display4

/* ******************************************* */

/* Start program and routine and interrupcion implementation */
.org 0x34

INIT:
	;Initial vlaues
		ldi r19, 0x00
		ldi r20, 0x00

	;Stack initialization
		ldi temp, low(RAMEND)
		out SPL, temp
		ldi temp, high(RAMEND)
		out SPH, temp

	;Config timer to modo1
		#define CLOCK 16.0e6 ;clock speed
		#define DELAY 1 ;the tima will update at each second
		.equ PRESCALE = 0b100 ;/256 prescale
		.equ PRESCALE_DIV = 256
		.equ WGM = 0b0100 ;Waveform generation mode: CTC
		;you must ensure this value is between 0 and 65535
		.equ TOP = int(0.5 + ((CLOCK/PRESCALE_DIV)*DELAY))
		.if TOP > 65535
		.error "TOP is out of range"
		.endif

	;Config the ports (DDR's)
		ldi temp, CI4511 | buzzer
		out DDRB, temp ; Port B is to CI4511 and buzzer

		ldi temp, displayes
		out DDRC, temp ; Port C is to transistors to select what display will be show the data. 

		ldi temp, buttons
		out DDRD, temp  ; Port D is to receiver the buttons and call the callbacks to system work very well

	;Enable especific interrupt


	sei

MAIN:


DELAY: ;Recebe o argumento da quantidade de delay em ms por r25
	ldi r26 , byte3(cloclkMHz * 1000 * r25 / 5)
	ldi r27, HIGH(byte3(cloclkMHz * 1000 * r25 / 5))
	ldi r28, LOW(byte3(cloclkMHz * 1000 * r25 / 5))

	sub	r28, 1
	sbci r27, 0
	sbci r26, 0
	brcc pc-3
	
	ret 

FUNC_BUZZER:
	cli ; critical secction - Desanable the global interrupt 
		ldi temp, buzzer
		out PORTB temp ; Estar errado por afeta os demais pinos

		ldi r25, 100 ; Await for 250ms until desanable the buzzefr

		ldi temp, buzzer & 0x00 ; Estar errado
		out PORTB temp
	sei ; Enable the global interrupt again
	ret



