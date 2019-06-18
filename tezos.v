From Coq
  Require Import ZArith String List.
Import ListNotations.
From mathcomp.ssreflect
  Require Import ssreflect ssrfun ssrbool ssrnat seq.

Set Implicit Arguments.

Section Data.

(* Inductive tez := Tez : nat -> tez. *)
Axiom tez : Type.
Axiom timestamp : Type.
Axiom int64 : Type.

(* for now, many items are commented as we are trying to get the
architecture right and don't want to get clogged with very similar
cases over and over. As we get more confident that we got things
right, we will uncomment new elements *)

Inductive tagged_data:=
| Int8 : Z -> tagged_data
(* | Int16 : Z -> tagged_data *)
(* | Int32 : Z -> tagged_data *)
| Int64 : int64 -> tagged_data
(* | Uint8 : Z -> tagged_data *)
(* | Uint16 : Z -> tagged_data *)
(* | Uint32 : Z -> tagged_data *)
(* | Uint64 : Z -> tagged_data *)
| Void
| Dtrue
| Dfalse
| DString : string -> tagged_data
(* | <float constant> *)
| Timestamp : timestamp -> tagged_data
(* | Signature <signature constant> *)
| DTez : tez -> tagged_data
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
| DPair : tagged_data -> tagged_data -> tagged_data.
(* | Pair <type> <type> <untagged data> <untagged data> *)
(* | List <type> <untagged data> ... *)
(* | Set <comparable type> <untagged data> ... *)
(* | Map <comparable type> <type> (Item <untagged data> <untagged data>) ... *)
(* | Contract <type> <type> <contract constant> *)
(* | Lambda <type> <type> { <instruction> ... } *)


Definition stack := list tagged_data.

Definition is_comparable (d : tagged_data) : bool :=
  match d with
    | Int8 z  => true
    | Int64 i => true
    | Dtrue | Dfalse => true
    | DTez t => true
    | _ => false
  end.

End Data.

Section Program.

(* In what follows, the "nested inductive types" approach calls for a custom (user-defined) induction principle *)

(* XXX: should we use a notation for `list instr` here? *)
Inductive instr :=
| Drop : instr
| Dup : instr
| Push : tagged_data -> instr
| Pair : instr
| If : list instr -> list instr -> instr
| Loop : list instr -> instr
| Le : instr
| Transfer_funds : instr
| Now : instr
| Balance : instr.

Definition program := list instr.

(* The custom induction principle for the `instr` datatype.
 *  We need it because the autogenerated `instr_ind` is too
 * weak for proofs.
 * Based on the approach described in
 * "Certified Programming with Dependent Types" book by A. Chlipala:
 * http://adam.chlipala.net/cpdt/html/InductiveTypes.html#lab32
 *)
Variable P : instr -> Prop.
Hypothesis Drop_case : P Drop.
Hypothesis Dup_case : P Dup.
Hypothesis Push_case : forall (d : tagged_data), P (Push d).
Hypothesis Pair_case : P Pair.
Hypothesis If_case : forall pgm1 pgm2 : program,
    Forall P pgm1 -> Forall P pgm2 -> P (If pgm1 pgm2).
Hypothesis Loop_case : forall pgm : program,
                         Forall P pgm -> P (Loop pgm).
Hypothesis Le_case : P Le.
Hypothesis Transfer_funds_case : P Transfer_funds.
Hypothesis Now_case : P Now.
Hypothesis Balance_case : P Balance.

Fixpoint instr_ind' (i : instr) : P i :=
  let list_instr_ind :=
      (fix list_instr_ind (pgm : program) : Forall P pgm :=
         match pgm with
         | [] => Forall_nil _
         | i' :: pgm' => Forall_cons _ (instr_ind' i') (list_instr_ind pgm')
         end) in
  match i with
  | Drop => Drop_case
  | Dup => Dup_case
  | Push d => Push_case d
  | Pair => Pair_case
  | If pgm1 pgm2 => If_case (list_instr_ind pgm1) (list_instr_ind pgm2)
  | Loop pgm => Loop_case (list_instr_ind pgm)
  | Le => Le_case
  | Transfer_funds => Transfer_funds_case
  | Now => Now_case
  | Balance => Balance_case
  end.

End Program.

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
program and programs *)

Inductive has_prog_type : program -> instr_type -> Prop :=
| PT_empty : forall st,
    has_prog_type nil (Pre_post st st)
| PT_seq : forall x xs sa sb sc,
    has_instr_type x (Pre_post sa sb) ->
    has_prog_type xs (Pre_post sb sc) ->
    has_prog_type (x::xs) (Pre_post sa sc)

with has_instr_type : instr -> instr_type -> Prop :=
| IT_Drop : forall s (t : type) (st : stack_type),
    has_stack_type s st ->
    has_instr_type Drop (Pre_post (cons_stack t st) (st))
| IT_Dup : forall s (t : type) (st : stack_type),
    has_stack_type s st ->
    has_instr_type Dup (Pre_post (cons_stack t st) (cons_stack t (cons_stack t st)))

| IT_If : forall sta stb bt bf xs,
    has_stack_type xs sta ->
    has_prog_type bt (Pre_post sta stb) ->
    has_prog_type bf (Pre_post sta stb) ->
    has_instr_type (If bt bf) (Pre_post (cons_stack t_bool sta) stb)
| IT_Loop : forall s a body,
    has_stack_type s (cons_stack t_bool a) ->
    has_prog_type body (Pre_post a (cons_stack t_bool a)) ->
    has_instr_type (Loop body) (Pre_post (cons_stack t_bool a) a)

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
by repeat econstructor.
Qed.

Lemma PT_instr_to_prog i t :
  has_instr_type i t ->
  has_prog_type [::i] t.
Proof.
by case: t; eauto.
Qed.

(* the clumsiness of this next one illustrates that it's probably not
a good idea to type an instruction against a stack, but to type a
program independently *)
Lemma PT_prog_to_instr i t :
  has_prog_type [::i] t ->
  has_instr_type i t.
Proof.
case: t => s0 s1 H.
inversion H; subst.
by inversion H5; subst.
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

Inductive step : instr * program * stack * memory ->
                 program * stack * memory -> Prop :=
| stepDrop : forall pgm x s m,
    step (Drop, pgm, x::s, m)
         (pgm, s, m)
| stepIfTrue : forall cont pgmT pgmF s m,
    step (If pgmT pgmF, cont, Dtrue :: s, m)
         (pgmT ++ cont, s, m)
| stepIfFalse : forall cont pgmT pgmF s m,
    step (If pgmT pgmF, cont, Dfalse :: s, m)
         (pgmF ++ cont, s, m)
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

(* I'm guessing these will be replaced by accesses to memory, with a
precise spec *)
Axiom get_timestamp : unit -> timestamp.
Axiom get_current_amount : unit -> tez.

(* these axioms to model the behavior of Transfer_funds, which I do
not understand as of now *)
Axiom get_new_global : tagged_data -> tagged_data.
Axiom get_return_value : tagged_data -> tagged_data.

Axiom get_le : tagged_data -> int64.

Fixpoint step_fun (i : instr) (pgm : program) (s : stack) (m : memory) : option (program * stack * memory) :=
  match i with
  | Drop => if s is x::xs then Some(pgm,xs,m) else None
  | Dup => if s is x::xs then Some(pgm,x::x::xs,m) else None
  | Push d => Some(pgm,d::s,m)
  | Pair => if s is a::b::s then Some(pgm,(DPair a b)::s,m) else None
  | If bt bf => if s is x::s then
                    match x with
                    | Dtrue => Some(bt++pgm,s,m)
                    | Dfalse => Some(bf++pgm,s,m)
                    | _ => None
                    end else None
  | Loop body => if s is x::s then
                  match x with
                  | Dtrue => Some(body++(Loop body :: pgm),s,m)
                  | Dfalse => Some(pgm,s,m)
                  | _ => None
                  end else None
  | Le => if s is x::s then if is_comparable x then Some(pgm,(Int64 (get_le x))::s,m) else None else None
  | Transfer_funds => if s is p::amount::contract::g::nil then
                  Some(pgm,[::get_return_value contract;get_new_global g],m) else None
  | Now => Some(pgm,Timestamp (get_timestamp tt)::s,m)
  | Balance => Some(pgm,DTez (get_current_amount tt)::s,m)
  end.

Fixpoint evaluate (pgm : program) (s : stack) (m : memory) (f : nat) : option (stack * memory) :=
  match f with
  | 0 => None
  | S f => match pgm with
          | nil => Some (s,m)
          | i::pgm => match (step_fun i pgm s m) with
                    | None => None
                    | Some(pgm',s',m') => evaluate pgm' s' m' f
                    end
          end
  end.

Lemma has_prog_type_cat : forall p q st1 st2 st3,
  has_prog_type p (Pre_post st1 st2) ->
  has_prog_type q (Pre_post st2 st3) ->
  has_prog_type (p++q) (Pre_post st1 st3).
Proof.
elim => [|p ps Hps] q st1 st2 st3.
- by move => Hnil; inversion Hnil.
- by move => Hp Hq; inversion Hp; econstructor; eauto.
Qed.

Lemma step_fun_preserves_type pgm st1 st2 s m f :
  has_prog_type pgm (Pre_post st1 st2) ->
  has_stack_type s st1 ->
  match (evaluate pgm s m f) with
  | Some (s',m') => has_stack_type s' st2
  | None => True
  end.
Proof.
move: f pgm st1 st2 s m.
elim => [|f HIf] pgm st1 st2 s m //.
case: pgm => [| i pgm] // .
  by move => HPT; inversion HPT => HST //=.
case: i => [| | (* Push *) d| | (* If *) bt bf| (* Loop *)body| (* Le *) | | |] /=.
- case: s => [| x s]// .
  move => HPT HST.
  inversion HPT.
  inversion HST.
  inversion H2.
  apply: HIf.
    exact: H4.
  rewrite -H8 in H10.
  case: H10.
    by move => _; rewrite -H11 => -> .
- admit. (* TODO : Dup *)
- admit. (* TODO : Push *)
- admit. (* TODO : Pair *)
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
          by rewrite -H7 => <- .
- admit. (* TODO : Le *)
- admit. (* TODO : Transfer_funds *)
- admit. (* TODO : Now *)
- admit. (* TODO : Balance *)
Admitted.

End Fun_semantics.

End Semantics.