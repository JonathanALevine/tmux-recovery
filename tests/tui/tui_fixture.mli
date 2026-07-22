open! Core
open Bonsai_term

val app
  :  dimensions:Dimensions.t Bonsai.t
  -> local_ Bonsai.graph
  -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t

val warning_app
  :  dimensions:Dimensions.t Bonsai.t
  -> local_ Bonsai.graph
  -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t

val empty_app
  :  dimensions:Dimensions.t Bonsai.t
  -> local_ Bonsai.graph
  -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t

val unavailable_app
  :  dimensions:Dimensions.t Bonsai.t
  -> local_ Bonsai.graph
  -> view:View.t Bonsai.t * handler:(Event.t -> unit Effect.t) Bonsai.t
