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

// Cyclic list with guard
//
// The actually interesting element is alway act.next, instead of act.
// This makes spawning a bit more complicated (has to spawn after next),
// but makes unlinking cheap (unlink next).

class CGList<T> implements haxe.rtti.Generic {

   public function new(guard: T) {
      act = new haxe.FastCell<T>(guard, null);
      act.next = act;
      should_unlink = false;
   }

   // Adds a new element after the next one
   //
   // (if we were adding after the current, then the
   // actual (=current.next) element would be run
   // again in this cycle later)
   public function spawn(e: T) {
      var _next = act.next;
      _next.next = new haxe.FastCell<T>(e, _next.next);
   }

   // Returns value of the next element
   inline public function next(): T {
      return act.next.elt;
   }

   inline public function advance() {
      if (should_unlink) {
         act.next = act.next.next;
         should_unlink = false;
      }
      else {
         act = act.next;
      }
   }

   // Marks next element for unlinking on advance
   inline public function mark_unlink() {
      should_unlink = true;
   }
   
   var act: haxe.FastCell<T>;
   var should_unlink: Bool;

}
