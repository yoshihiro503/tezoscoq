From Coq
  Require Import ZArith String List.
Import ListNotations.
From mathcomp.ssreflect
  Require Import ssreflect ssrfun ssrbool ssrnat seq.

Set Implicit Arguments.

Section Data.

Inductive tez := Tez : nat -> tez.

(* for now, many items are commented as we are trying to get the
architecture right and don't want to get clogged with very similar
cases over and over. As we get more confident that we got things
right, we will uncomment new elements *)

Inductive tagged_data:=
| Int8 : Z -> tagged_data
(* | Int16 : Z -> tagged_data *)
(* | Int32 : Z -> tagged_data *)
(* | Int64 : Z -> tagged_data *)
(* | Uint8 : Z -> tagged_data *)
(* | Uint16 : Z -> tagged_data *)
(* | Uint32 : Z -> tagged_data *)
(* | Uint64 : Z -> tagged_data *)
| Void
| Dtrue
| Dfalse
| DString : string -> tagged_data
(* | <float constant> *)
(* | Timestamp <timestamp constant> *)
(* | Signature <signature constant> *)
| DTez : tez -> tagged_data.
(* | Key <key constant> *)
(* | Left <tagged data> <type> *)
(* | Right <type> <tagged data> *)
(* | Or <type> <type> <untagged data> *)
(* | Ref <tagged data> *)
(* | Ref <type> <untagged data> *)
(* | Some <tagged data> *)
(* | Some <type> <untagged data> *)
(* | None <type> *)
(* | Option <type> <untagged data> *)
(* | Pair <tagged data> <tagged data> *)
(* | Pair <type> <type> <untagged data> <untagged data> *)
(* | List <type> <untagged data> ... *)
(* | Set <comparable type> <untagged data> ... *)
(* | Map <comparable type> <type> (Item <untagged data> <untagged data>) ... *)
(* | Contract <type> <type> <contract constant> *)
(* | Lambda <type> <type> { <instruction> ... } *)


Definition stack := list tagged_data.

End Data.

Section Instructions.

(* In what follows, the "nested inductive types" approach calls for a custom (user-defined) induction principle *)

(* XXX: should we use a notation for `list instr` here? *)
Inductive instr :=
| Drop : instr
| If : list instr -> list instr -> instr
| Loop : list instr -> instr.

Definition instructions := list instr.

(* The custom induction principle for the `instr` datatype.
 *  We need it because the autogenerated `instr_ind` is too
 * weak for proofs.
 * Based on the approach described in
 * "Certified Programming with Dependent Types" book by A. Chlipala:
 * http://adam.chlipala.net/cpdt/html/InductiveTypes.html#lab32
 *)
Variable P : instr -> Prop.
Hypothesis Drop_case : P Drop.
Hypothesis If_case : forall ins1 ins2 : instructions,
    Forall P ins1 -> Forall P ins2 -> P (If ins1 ins2).
Hypothesis Loop_case : forall ins : instructions,
    Forall P ins -> P (Loop ins).
Fixpoint instr_ind' (i : instr) : P i :=
  let list_instr_ind :=
      (fix list_instr_ind (ins : instructions) : Forall P ins :=
         match ins with
         | [] => Forall_nil _
         | i' :: ins' => Forall_cons _ (instr_ind' i') (list_instr_ind ins')
         end) in
  match i with
  | Drop => Drop_case
  | If ins1 ins2 => If_case (list_instr_ind ins1) (list_instr_ind ins2)
  | Loop ins => Loop_case (list_instr_ind ins)
  end.
End Instructions.

Section Types.

Inductive instr_type :=
| Pre_post : stack_type -> stack_type -> instr_type

with stack_type :=
| empty_stack : stack_type
| cons_stack : type -> stack_type -> stack_type

with type :=
| t_int8 : type
| t_void : type
| t_bool : type
| t_string : type
| t_tez : tez -> type
| t_contract : type -> type -> type
| t_quotation : instr_type -> type.

(* * `lambda T_arg T_ret` is a shortcut for `[ T_arg :: [] -> T_ret :: []]`. *)
Definition lambda t_arg t_ret :=
  t_quotation (Pre_post (cons_stack t_arg empty_stack) (cons_stack t_ret empty_stack)).

End Types.

Section Typing.
(* Here we want to talk about typing judgements, for data,
instructions and programs *)

Inductive has_prog_type : list instr -> instr_type -> Prop :=
| PT_empty : forall st,
    has_prog_type nil (Pre_post st st)
| PT_seq : forall x xs s sa sb sc,
    has_instr_type x s (Pre_post sa sb) ->
    has_prog_type xs (Pre_post sb sc) ->
    has_prog_type (x::xs) (Pre_post sa sc)

with has_instr_type : instr -> stack -> instr_type -> Prop :=
| IT_Drop : forall x s (t : type) (st : stack_type),
    has_stack_type s st ->
    has_type x t ->
    has_instr_type Drop (x::s) (Pre_post (cons_stack t st) (st))

| IT_If : forall bvar sta stb bt bf xs,
    has_type bvar t_bool ->
    has_stack_type xs sta ->
    has_prog_type bt (Pre_post sta stb) ->
    has_prog_type bf (Pre_post sta stb) ->
    has_instr_type (If bt bf) (bvar::xs) (Pre_post (cons_stack t_bool sta) stb)
| IT_Loop : forall s a body,
    has_stack_type s (cons_stack t_bool a) ->
    has_prog_type body (Pre_post a (cons_stack t_bool a)) ->
    has_instr_type (Loop body) s (Pre_post (cons_stack t_bool a) a)

with has_stack_type : stack -> stack_type -> Prop :=
| ST_empty : has_stack_type nil empty_stack
| ST_cons : forall x xs t st,
    has_type x t ->
    has_stack_type xs st ->
    has_stack_type (x::xs) (cons_stack t st)

with has_type : tagged_data -> type -> Prop :=
| T_boolT : has_type Dtrue t_bool
| T_boolF : has_type Dfalse t_bool.

(* is this useful? *)
Scheme has_prog_type_ind' := Induction for has_prog_type Sort Prop
with has_instr_type_ind' := Induction for has_instr_type Sort Prop
with has_stack_type_ind' := Induction for has_stack_type Sort Prop
with has_type_ind' := Induction for has_type Sort Prop.

(* Print has_prog_type_ind. *)
(* Print has_prog_type_ind'. *)

Hint Constructors has_prog_type.
Hint Constructors has_instr_type.
Hint Constructors has_stack_type.
Hint Constructors has_type.

(* test *)
Example Drop_typing_with_empty_stack :
  has_prog_type [::Drop] (Pre_post (cons_stack t_bool empty_stack)
                                   (empty_stack)).
Proof.
repeat econstructor.
Qed.

Lemma PT_instr_to_prog i s t :
  has_instr_type i s t ->
  has_prog_type [::i] t.
Proof.
case: t; eauto.
Qed.

(* the clumsiness of this next one illustrates that it's probably not
a good idea to type an instruction against a stack, but to type a
program independently *)
Lemma PT_prog_to_instr i t :
  has_prog_type [::i] t ->
  exists s, has_instr_type i s t.
Proof.
case: t => s0 s1 H.
inversion H; subst.
inversion H5; subst.
now exists s.
Qed.

End Typing.

Section Semantics.

(* To be changed once we know what we want *)
Variables memory : Type.

(* until we get a better sense of what works best, we will try two
ways to do the small steps semantics: one with an inductive type of
reduction rules, and one with a step function. *)

(* First version: inductive semantics *)
Section Ind_semantics.

Inductive step : instr * instructions * stack * memory ->
                 instructions * stack * memory -> Prop :=
| stepDrop : forall ins x s m,
    step (Drop, ins, x::s, m)
         (ins, s, m)
| stepIfTrue : forall cont insT insF s m,
    step (If insT insF, cont, Dtrue :: s, m)
         (insT ++ cont, s, m)
| stepIfFalse : forall cont insT insF s m,
    step (If insT insF, cont, Dfalse :: s, m)
         (insF ++ cont, s, m)
| stepLoopGo : forall cont body s m,
    step (Loop body, cont, Dtrue :: s, m)
         (body ++ (Loop body :: cont), s, m)
| stepLoopEnd : forall cont body s m,
    step (Loop body, cont, Dfalse :: s, m)
         (cont, s, m)
.

End Ind_semantics.


(* Second version: with a step function *)
Section Fun_semantics.

Fixpoint step_fun (i : instr) (ix : instructions) (s : stack) (m : memory) : option (instructions * stack * memory) :=
  match i with
  | Drop => if s is x::xs then Some(ix,xs,m) else None
  | If bt bf => if s is x::s then
                    match x with
                    | Dtrue => Some(bt++ix,s,m)
                    | Dfalse => Some(bf++ix,s,m)
                    | _ => None
                    end else None
    | Loop body => if s is x::s then
                  match x with
                  | Dtrue => Some(body++(Loop body :: ix),s,m)
                  | Dfalse => Some(ix,s,m)
                  | _ => None
                  end else None
  end.

Fixpoint evaluate (ix : instructions) (s : stack) (m : memory) (f : nat) : option (stack * memory) :=
  match f with
  | 0 => None
  | S f => match ix with
          | nil => Some (s,m)
          | i::ix => match (step_fun i ix s m) with
                    | None => None
                    | Some(ix',s',m') => evaluate ix' s' m' f
                    end
          end
  end.

Lemma has_prog_type_cat : forall p q st1 st2 st3,
  has_prog_type p (Pre_post st1 st2) ->
  has_prog_type q (Pre_post st2 st3) ->
  has_prog_type (p++q) (Pre_post st1 st3).
Proof.
elim => [|p ps Hps] /=.
- move => q st1 st2 st3.
  move => Hnil.
  by inversion Hnil.
- move => q st1 st2 st3.
  move => Hp Hq.
  inversion Hp.
  apply: PT_seq; last first.
  apply: Hps.
    exact: H4.
  exact: Hq.
  exact: H2.
Qed.

Lemma step_fun_preserves_type instrs st1 st2 s m f :
  has_prog_type instrs (Pre_post st1 st2) ->
  has_stack_type s st1 ->
  match (evaluate instrs s m f) with
  | Some (s',m') => has_stack_type s' st2
  | None => True
  end.
Proof.
move: f instrs st1 st2 s m.
elim => [|f HIf] instrs st1 st2 s m //.
case: instrs => [| i instrs] // .
  by move => HPT; inversion HPT => HST //=.
case: i => [|bt bf|body] /=.
- case: s => [| x s]// .
  move => HPT HST.
  inversion HPT.
  inversion HST.
  inversion H2.
  have toto := HIf.
  apply: HIf.
    exact: H4.
  rewrite -H8 in H10.
  case: H10.
  by move => _; rewrite -H11 => ->.
- case: s => [| x s] //; case: x => // .
  + move => HPT HST.
    inversion HPT.
    inversion H2.
    apply: HIf.
      apply: has_prog_type_cat.
        exact: H12.
        exact: H4.
    rewrite -H7 in HST.
    by inversion HST.
  + move => HPT HST.
    inversion HPT.
    inversion H2.
    apply: HIf.
      apply: has_prog_type_cat.
        exact: H13.
        exact: H4.
    rewrite -H7 in HST.
    by inversion HST.
- case: s => [| x s] //; case: x => // ; last first.
  + move => HPT HST.
    inversion HPT.
    apply: HIf.
      exact: H4.
    inversion HST.
    inversion H2.
    rewrite -H8 in H11.
    case: H11 => _.
    by rewrite -H12 => -> .
  + move => HPT HST.
    inversion HPT.
    inversion H2.
    apply: HIf.
      * apply: has_prog_type_cat.
          exact: H10.
        apply: PT_seq.
          apply: IT_Loop.
            exact: H9.
          exact: H10.
        exact: H4.
      * inversion HST.
        rewrite -H6 in H14.
        case: H14 => _.
        by rewrite -H7 => <-.
Qed.

End Fun_semantics.

End Semantics.