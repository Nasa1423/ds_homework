.include "m8def.inc"
.equ FRAME = 8192
.equ B_PHASE = 3200
.equ QUIET_PHASE = 6400
.equ WAIT_EARLY = 20
.equ RX_GUARD = 80
.equ TIMER1_INTERVAL = 2*FRAME
.equ TIMER2_INTERVAL = 3*FRAME
.if (TIMER1_INTERVAL < FRAME) || (TIMER1_INTERVAL > 9*FRAME) || (TIMER1_INTERVAL & (FRAME-1))
 .error "TIMER1_INTERVAL must be 1..9 whole frames"
.endif
.if (TIMER2_INTERVAL < FRAME) || (TIMER2_INTERVAL > 9*FRAME) || (TIMER2_INTERVAL & (FRAME-1))
 .error "TIMER2_INTERVAL must be 1..9 whole frames"
.endif
.dseg
.org 0x60
period1: .byte 1
period2: .byte 1
length1: .byte 1
length2: .byte 1
count1: .byte 1
count2: .byte 1
cmd_len: .byte 1
cmd_bad: .byte 1
cmd_ready: .byte 1
string1: .byte 18
string2: .byte 18
reply_ok: .byte 5
reply_error: .byte 6
state_end:
.org 0x100
command: .byte 19
.cseg
.org 0
 rjmp reset
.org INT_VECTORS_SIZE
reset:
 cli
 ldi r16,high(RAMEND)
 out SPH,r16
 ldi r16,low(RAMEND)
 out SPL,r16
 clr r1
 ldi XL,low(period1)
 clr XH
 ldi r20,state_end-period1
clear_state:
 st X+,r1
 dec r20
 brne clear_state
 ldi r16,TIMER1_INTERVAL/FRAME
 sts period1,r16
 sts count1,r16
 ldi r16,TIMER2_INTERVAL/FRAME
 sts period2,r16
 ldi r16,1
 sts count2,r16
 ldi r16,4
 sts length1,r16
 sts length2,r16
 ldi ZL,low(defaults*2)
 ldi ZH,high(defaults*2)
 ldi XL,low(string1)
 ldi r20,6
 rcall flash_copy
 ldi XL,low(string2)
 ldi r20,6
 rcall flash_copy
 ldi XL,low(reply_ok)
 ldi r20,11
 rcall flash_copy
 out UBRRH,r1
 out UBRRL,r1
 ldi r16,(1<<URSEL)|(1<<UCSZ1)|(1<<UCSZ0)
 out UCSRC,r16
 ldi r16,(1<<RXEN)|(1<<TXEN)
 out UCSRB,r16
 out TCCR1A,r1
 out TCCR1B,r1
 ldi r20,'p'
 out UDR,r20
sync_start:
 sbic PIND,PD1
 rjmp sync_start
 ldi r16,8
 out TCNT1H,r1
 out TCNT1L,r16
 ldi r16,(1<<CS10)
 out TCCR1B,r16
 clr YL
 clr YH
 ldi ZL,low(string1+1)
 clr ZH
 ldi r21,5
 rcall send_more
 rjmp slot_b

frame_a:
 lds r20,count1
 dec r20
 sts count1,r20
 brne slot_b
 lds r20,period1
 sts count1,r20
 ldi ZL,low(string1)
 clr ZH
 lds r21,length1
 subi r21,-2
 movw r24,YL
 rcall send_scheduled
slot_b:
 lds r20,count2
 dec r20
 sts count2,r20
 brne quiet_wait
 lds r20,period2
 sts count2,r20
 ldi ZL,low(string2)
 clr ZH
 lds r21,length2
 subi r21,-2
 movw r24,YL
 subi r24,low(-B_PHASE)
 sbci r25,high(-B_PHASE)
 rcall send_scheduled
quiet_wait:
 movw r24,YL
 subi r24,low(-(QUIET_PHASE+WAIT_EARLY))
 sbci r25,high(-(QUIET_PHASE+WAIT_EARLY))
 rcall wait_slot
quiet_poll:
 rcall receive_poll
 in r16,TCNT1L
 in r17,TCNT1H
 sub r17,YH
 cpi r17,26
 brsh next_frame
 lds r16,cmd_ready
 tst r16
 breq quiet_poll
 rcall execute_command
next_frame:
 subi YH,-32
 rjmp frame_a

send_scheduled:
 ld r20,Z+
 rcall wait_slot
 out UDR,r20
 dec r21
send_more:
 rcall receive_poll
 sbis UCSRA,UDRE
 rjmp send_more
 ld r20,Z+
 out UDR,r20
 dec r21
 brne send_more
 ret
wait_slot:
 sbiw r24,WAIT_EARLY
far_wait:
 in r16,TCNT1L
 in r17,TCNT1H
 sub r16,r24
 sbc r17,r25
 sbrs r17,7
 rjmp tight_wait
 cpi r17,0xFF
 brne poll_far
 cpi r16,low(-RX_GUARD)
 brsh tight_wait
poll_far:
 rcall receive_poll
 rjmp far_wait
tight_wait:
 in r16,TCNT1L
 in r17,TCNT1H
 sub r16,r24
 sbc r17,r25
 sbrc r17,7
 rjmp tight_wait
 ret

receive_poll:
 sbis UCSRA,RXC
 ret
 in r16,UCSRA
 in r17,UDR
 push XL
 push XH
 lds r18,cmd_ready
 tst r18
 brne received
 andi r16,(1<<FE)|(1<<DOR)|(1<<PE)
 brne bad_byte
 cpi r17,10
 breq line_complete
 cpi r17,13
 breq received
 cpi r17,32
 brlo bad_byte
 cpi r17,127
 brsh bad_byte
 lds r18,cmd_len
 cpi r18,19
 brsh bad_byte
 mov XL,r18
 ldi XH,high(command)
 st X,r17
 inc r18
 sts cmd_len,r18
 rjmp received
line_complete:
 ldi r18,1
 sts cmd_ready,r18
 rjmp received
bad_byte:
 ldi r18,1
 sts cmd_bad,r18
received:
 pop XH
 pop XL
 ret

execute_command:
 lds r16,cmd_bad
 tst r16
 breq parse_good
 rjmp bad_command
parse_good:
 lds r20,cmd_len
 lds r22,command
 cpi r20,1
 brne parse_pair
 cpi r22,'R'
 breq restart_counters
 rjmp bad_command
parse_pair:
 cpi r20,3
 brlo bad_command
 lds r23,command+1
 subi r23,'1'
 cpi r23,2
 brsh bad_command
 lds r16,command+2
 cpi r16,' '
 brne bad_command
 cpi r22,'S'
 breq copy_string
 cpi r22,'T'
 brne bad_command
 cpi r20,4
 brne bad_command
 lds r21,command+3
 subi r21,'1'
 cpi r21,9
 brsh bad_command
 inc r21
 ldi XL,low(period1)
 clr XH
 add XL,r23
 st X,r21
 rjmp restart_counters
copy_string:
 subi r20,3
 tst r20
 breq string_valid
 lds r16,command+3
 cpi r16,'!'
 breq bad_command
string_valid:
 ldi XL,low(length1)
 clr XH
 add XL,r23
 st X,r20
 ldi XL,low(string1)
 tst r23
 breq string_selected
 ldi XL,low(string2)
string_selected:
 ldi ZL,low(command+3)
 ldi ZH,high(command+3)
 mov r25,r20
 tst r25
 breq string_end
copy_byte:
 ld r19,Z+
 st X+,r19
 rcall receive_poll
 dec r25
 brne copy_byte
string_end:
 ldi r16,13
 st X+,r16
 ldi r16,10
 st X,r16
restart_counters:
 ldi r16,1
 sts count1,r16
 sts count2,r16
 ldi ZL,low(reply_ok)
 ldi r21,5
 rjmp reply
bad_command:
 ldi ZL,low(reply_error)
 ldi r21,6
reply:
 sts cmd_len,r1
 sts cmd_bad,r1
 sts cmd_ready,r1
 clr ZH
 rjmp send_more
flash_copy:
 lpm r16,Z+
 st X+,r16
 dec r20
 brne flash_copy
 ret
defaults: .db "ping",13,10,"pong",13,10,"!OK",13,10,"!ERR",13,10,0
