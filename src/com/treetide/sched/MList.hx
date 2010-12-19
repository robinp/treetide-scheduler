/*
   Copyright (c) 2010, the haXe Project Contributors
   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions are met:

      * Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.

      * Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
   ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
   WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
   DISCLAIMED. IN NO EVENT SHALL THE HAXE PROJECT CONTRIBUTORS BE LIABLE FOR ANY
   DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
   (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
   LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
   ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

package com.treetide.sched;

import haxe.FastList;

// Simple queue for messages of a process

class MList<T> {

   public function new() {
      reinit();
   }

   public function reinit() {
      head = prev = tail = null;
   }

   // A process can flush the message queue
   public function flush() {
      reinit();
   }

   public function dump(sep = " --> ") {
      var s = "";
      var p = head;
      while (p != null) {
         s += Std.string(p.elt) + sep;
         p = p.next;
      }
      s += "null";
      return s;
   }

   // When a new message is sent, it is
   // appended to the list
   public function add(e: T) {
      if (tail == null) {
         tail = head = new haxe.FastCell<T>(e, null);
      }
      else {
         tail.next = new haxe.FastCell<T>(e, null);
         tail = tail.next;
      }
   }

   inline function next_cell() {
      return if (prev == null)
         head
      else 
         prev.next;
   }

   // When a process is waked from PMWait, it
   // peeks the message
   //
   // Returns null if no more message
   public function peek_next(): Null<T> {
      var next = next_cell();
      return next == null ? null : next.elt;
   }

   // The process can refuse to accept the message yet,
   // so the current pointer is advanced
   public function advance() {
      var next = next_cell();
      prev = next;
   }


   // The process can also accept the message, so it
   // gets unlinked
   inline function unlink() {
      if (prev == null) {
         // unlink head
         head = head.next;
         if (head == null) {
            tail =  null;
         }
      }
      else {
         // unlink current
         if (prev == null) {
            // deleting current head

            if (head == tail) {
               // list becomes empty
               tail = null;
            }

            head = head.next;
         }
         else {
            if (tail == prev.next) {
               // if current is the tail, then 
               // tail becomes the previous 
               // after the unlink
               tail = prev;
            }

            prev.next = prev.next.next;
         }
      }
   }

   // After accepting a message, the queue
   // position should be rewind, so that new
   // PMWait rechecks already queued messages
   inline public function rewind() {
      prev = null;
   }
 
   // consumes the current message
   public function consume() {
      unlink();
      rewind();
   }

   // ----- members -----

   var head: haxe.FastCell<T>;
   var tail: haxe.FastCell<T>;

   // prev points to before the last checked (and possibly refused)
   // item
   var prev: haxe.FastCell<T>;

}
