/*
 * Scala (https://www.scala-lang.org)
 *
 * Copyright EPFL and Lightbend, Inc. dba Akka
 *
 * Licensed under Apache License 2.0
 * (http://www.apache.org/licenses/LICENSE-2.0).
 *
 * See the NOTICE file distributed with this work for
 * additional information regarding copyright ownership.
 */

package scala

import java.lang.System.{currentTimeMillis => currentTime}

import scala.annotation.nowarn
import scala.collection.mutable.ListBuffer

/** The `App` trait can be used to quickly turn objects
 *  into executable programs. Here is an example:
 *  {{{
 *  object Main extends App {
 *    Console.println("Hello World: " + (args mkString ", "))
 *  }
 *  }}}
 *
 *  No explicit `main` method is needed.  Instead,
 *  the whole class body becomes the “main method”.
 *
 *  `args` returns the current command line arguments as an array.
 *
 *  ==Caveats==
 *
 *  '''''It should be noted that this trait is implemented using the [[DelayedInit]]
 *  functionality, which means that fields of th
