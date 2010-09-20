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
