open! Core
module I32 = Stdlib.Int32
module I64 = Stdlib.Int64

let constants =
  [| 0x428a2f98l
   ; 0x71374491l
   ; 0xb5c0fbcfl
   ; 0xe9b5dba5l
   ; 0x3956c25bl
   ; 0x59f111f1l
   ; 0x923f82a4l
   ; 0xab1c5ed5l
   ; 0xd807aa98l
   ; 0x12835b01l
   ; 0x243185bel
   ; 0x550c7dc3l
   ; 0x72be5d74l
   ; 0x80deb1fel
   ; 0x9bdc06a7l
   ; 0xc19bf174l
   ; 0xe49b69c1l
   ; 0xefbe4786l
   ; 0x0fc19dc6l
   ; 0x240ca1ccl
   ; 0x2de92c6fl
   ; 0x4a7484aal
   ; 0x5cb0a9dcl
   ; 0x76f988dal
   ; 0x983e5152l
   ; 0xa831c66dl
   ; 0xb00327c8l
   ; 0xbf597fc7l
   ; 0xc6e00bf3l
   ; 0xd5a79147l
   ; 0x06ca6351l
   ; 0x14292967l
   ; 0x27b70a85l
   ; 0x2e1b2138l
   ; 0x4d2c6dfcl
   ; 0x53380d13l
   ; 0x650a7354l
   ; 0x766a0abbl
   ; 0x81c2c92el
   ; 0x92722c85l
   ; 0xa2bfe8a1l
   ; 0xa81a664bl
   ; 0xc24b8b70l
   ; 0xc76c51a3l
   ; 0xd192e819l
   ; 0xd6990624l
   ; 0xf40e3585l
   ; 0x106aa070l
   ; 0x19a4c116l
   ; 0x1e376c08l
   ; 0x2748774cl
   ; 0x34b0bcb5l
   ; 0x391c0cb3l
   ; 0x4ed8aa4al
   ; 0x5b9cca4fl
   ; 0x682e6ff3l
   ; 0x748f82eel
   ; 0x78a5636fl
   ; 0x84c87814l
   ; 0x8cc70208l
   ; 0x90befffal
   ; 0xa4506cebl
   ; 0xbef9a3f7l
   ; 0xc67178f2l
  |]
;;

let rotate_right value bits =
  I32.logor (I32.shift_right_logical value bits) (I32.shift_left value (32 - bits))
;;

let padded input =
  let input_length = String.length input in
  let padded_length = (input_length + 9 + 63) / 64 * 64 in
  let bytes = Bytes.make padded_length '\000' in
  String.iteri input ~f:(fun index character -> Bytes.set bytes index character);
  Bytes.set bytes input_length '\x80';
  let bit_length = I64.mul (I64.of_int input_length) 8L in
  for index = 0 to 7 do
    let shift = (7 - index) * 8 in
    let byte = I64.(to_int (logand (shift_right_logical bit_length shift) 0xffL)) in
    Bytes.set bytes (padded_length - 8 + index) (Char.of_int_exn byte)
  done;
  bytes
;;

let word bytes offset =
  let byte index = Char.to_int (Bytes.get bytes (offset + index)) |> I32.of_int in
  I32.logor
    (I32.shift_left (byte 0) 24)
    (I32.logor
       (I32.shift_left (byte 1) 16)
       (I32.logor (I32.shift_left (byte 2) 8) (byte 3)))
;;

let digest_string input =
  let bytes = padded input in
  let state =
    [| 0x6a09e667l
     ; 0xbb67ae85l
     ; 0x3c6ef372l
     ; 0xa54ff53al
     ; 0x510e527fl
     ; 0x9b05688cl
     ; 0x1f83d9abl
     ; 0x5be0cd19l
    |]
  in
  for chunk = 0 to (Bytes.length bytes / 64) - 1 do
    let words = Array.create ~len:64 0l in
    for index = 0 to 15 do
      words.(index) <- word bytes ((chunk * 64) + (index * 4))
    done;
    for index = 16 to 63 do
      let value_15 = words.(index - 15) in
      let sigma_0 =
        I32.logxor
          (rotate_right value_15 7)
          (I32.logxor (rotate_right value_15 18) (I32.shift_right_logical value_15 3))
      in
      let value_2 = words.(index - 2) in
      let sigma_1 =
        I32.logxor
          (rotate_right value_2 17)
          (I32.logxor (rotate_right value_2 19) (I32.shift_right_logical value_2 10))
      in
      words.(index)
      <- I32.add (I32.add words.(index - 16) sigma_0) (I32.add words.(index - 7) sigma_1)
    done;
    let a = ref state.(0)
    and b = ref state.(1)
    and c = ref state.(2)
    and d = ref state.(3)
    and e = ref state.(4)
    and f = ref state.(5)
    and g = ref state.(6)
    and h = ref state.(7) in
    for index = 0 to 63 do
      let sum_1 =
        I32.logxor
          (rotate_right !e 6)
          (I32.logxor (rotate_right !e 11) (rotate_right !e 25))
      in
      let choose = I32.logxor (I32.logand !e !f) (I32.logand (I32.lognot !e) !g) in
      let temporary_1 =
        I32.add
          (I32.add (I32.add (I32.add !h sum_1) choose) constants.(index))
          words.(index)
      in
      let sum_0 =
        I32.logxor
          (rotate_right !a 2)
          (I32.logxor (rotate_right !a 13) (rotate_right !a 22))
      in
      let majority =
        I32.logxor (I32.logand !a !b) (I32.logxor (I32.logand !a !c) (I32.logand !b !c))
      in
      let temporary_2 = I32.add sum_0 majority in
      h := !g;
      g := !f;
      f := !e;
      e := I32.add !d temporary_1;
      d := !c;
      c := !b;
      b := !a;
      a := I32.add temporary_1 temporary_2
    done;
    state.(0) <- I32.add state.(0) !a;
    state.(1) <- I32.add state.(1) !b;
    state.(2) <- I32.add state.(2) !c;
    state.(3) <- I32.add state.(3) !d;
    state.(4) <- I32.add state.(4) !e;
    state.(5) <- I32.add state.(5) !f;
    state.(6) <- I32.add state.(6) !g;
    state.(7) <- I32.add state.(7) !h
  done;
  Array.to_list state |> List.map ~f:(Printf.sprintf "%08lx") |> String.concat
;;
