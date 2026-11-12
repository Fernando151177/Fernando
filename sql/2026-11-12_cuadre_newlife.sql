-- FinanzasApp · cuadre con NEW LIFE · 12/11/2026
-- Proyecto Supabase: junobvvcitsvpzafmmct
-- Ejecutar BLOQUE A BLOQUE y comprobar las filas esperadas antes de seguir.
-- user_id va explícito (a6fd07ad-06e4-41cb-8226-0747c24a6543) porque auth.uid() es NULL fuera de sesión.

-- ============ BLOQUE 0 · COPIA DE SEGURIDAD ============
create schema if not exists backup_20261112b;
create table backup_20261112b.transactions          as select * from public.transactions;
create table backup_20261112b.journal_entries       as select * from public.journal_entries;
create table backup_20261112b.compromisos           as select * from public.compromisos;
create table backup_20261112b.loan_payments         as select * from public.loan_payments;
create table backup_20261112b.amortizaciones_extra  as select * from public.amortizaciones_extra;
create table backup_20261112b.subcuentas            as select * from public.subcuentas;
create table backup_20261112b.recurring_transactions as select * from public.recurring_transactions;
create table backup_20261112b.loans                 as select * from public.loans;

-- ============ BLOQUE 1 · 471,90 € (Caso 1, 2º pago): no salió de BBVA ============
-- 1.1 Desligar el compromiso de su transacción (FK) y dejarlo pendiente. Esperado: 1 fila.
update public.compromisos
   set pagado = false,
       transaction_id = null,
       fecha = '2027-01-31',
       notas = coalesce(notas,'') || E'\n12/11/2026: sin cargo en BBVA el 19/05/2026 (extracto mar-jun). Vence max. 7 dias tras admision de la demanda (hoja de encargo 19/02/2026). Fecha = estimacion.'
 where id = 'cdc45665-8557-429a-a825-3a20038f28ab' and pagado = true;

-- 1.2 Borrar la transacción falsa (sus apuntes caen en cascada). Esperado: 1 fila.
delete from public.transactions
 where id = 'efa93515-2a9d-4963-a289-d93b8e0c658a'
   and description like 'Caso 1 · 2º pago%';

-- 1.3 314,60 €: quitar la fecha inventada 20/06/2026. Esperado: 1 fila.
update public.compromisos
   set fecha = '2027-01-31',
       notas = coalesce(notas,'') || E'\n12/11/2026: sin fecha contractual; vence max. 7 dias tras contestacion o rebeldia. Fecha = estimacion (plan ene-feb 2027).'
 where id = '36254cd0-9912-4432-993b-d0f9ec1c66f6' and pagado = false;

-- ============ BLOQUE 2 · 30/10: 588,40 € = 582,60 amortización + 5,80 comisión (BBVA NUEVO) ============
-- 2.1 Corregir la transacción existente (antes iba a 2000-061 BBVA, el préstamo antiguo).
update public.journal_entries
   set amount = -582.60, memo = 'Amortización anticipada BBVA NUEVO'
 where id = 'e58004fb-2a63-4d83-9eb3-2dbef5709ff1';                       -- Cuenta Corriente. Esperado: 1

update public.journal_entries
   set amount = 582.60, memo = 'Amortización anticipada BBVA NUEVO',
       account_id = (select id from public.accounts where code = '2000-902')
 where id = 'd96b9c94-2e7a-429b-afda-38f24ac153b2';                       -- Esperado: 1

update public.transactions
   set description = 'Amortización anticipada BBVA NUEVO', loan_id = null  -- mismo patrón que la del 24/09
 where id = 'b7b6751e-ad5f-47d0-a2cd-ed4f375df204';                       -- Esperado: 1

-- 2.2 Comisión de 5,80 € (misma cuenta 2000-902, como la comisión de 15,00 del 24/09). Esperado: 1 transacción, 2 apuntes.
with t as (
  insert into public.transactions (date, description, user_id)
  select '2026-10-30', 'Comisión amortización anticipada BBVA NUEVO', 'a6fd07ad-06e4-41cb-8226-0747c24a6543'::uuid
   where not exists (select 1 from public.transactions
                      where date = '2026-10-30' and description like 'Comisión amortización anticipada%')
  returning id
)
insert into public.journal_entries (transaction_id, account_id, amount, memo, user_id)
select t.id, (select id from public.accounts where code = '1000'), -5.80,
       'Comisión amortización anticipada BBVA NUEVO', 'a6fd07ad-06e4-41cb-8226-0747c24a6543'::uuid from t
union all
select t.id, (select id from public.accounts where code = '2000-902'), 5.80,
       'Comisión amortización anticipada BBVA NUEVO', 'a6fd07ad-06e4-41cb-8226-0747c24a6543'::uuid from t;

-- 2.3 loan_payments: era "cuota" de 588,40; es amortización de 582,60. Esperado: 1 fila.
update public.loan_payments
   set type = 'amortizacion', amount = 582.60,
       note = 'Amortización anticipada 30/10/2026 (comisión 5,80 aparte)', estado_dato = 'verificado'
 where loan_id = 'a8d3caaa-0b35-475b-b8d4-a642a42491a4'
   and date = '2026-10-30' and amount = 588.40;

-- 2.4 amortizaciones_extra: registrar la ejecutada. Esperado: 1 fila.
insert into public.amortizaciones_extra (user_id, loan_id, fecha, importe, ejecutado, estado_dato)
select 'a6fd07ad-06e4-41cb-8226-0747c24a6543'::uuid, 'a8d3caaa-0b35-475b-b8d4-a642a42491a4'::uuid,
       '2026-10-30', 582.60, true, 'verificado'
 where not exists (select 1 from public.amortizaciones_extra
                    where loan_id = 'a8d3caaa-0b35-475b-b8d4-a642a42491a4' and fecha = '2026-10-30');

-- 2.5 OPCIONAL · la del 24/09 real fue 1.505,38 (V, extracto BBVA); la app tiene 1.500,00.
--     Solo si Fernando lo aprueba. Esperado: 1 fila en cada una.
-- update public.amortizaciones_extra set importe = 1505.38
--  where id = '15e51f81-e5cc-4578-bc99-a1cb4d197fc8';
-- update public.loan_payments set amount = 1505.38
--  where loan_id = 'a8d3caaa-0b35-475b-b8d4-a642a42491a4' and date = '2026-09-24' and type = 'amortizacion';

-- ============ BLOQUE 3 · SEGURO MINI 51,80 € ============
-- 3.1 Quitar 51,80 de loan_payments del MINI (no es cuota del préstamo). Esperado: 6 filas.
delete from public.loan_payments
 where loan_id = '2d70a5bc-7c7f-404b-9cad-9f4a24fa902a' and type = 'cuota' and amount = 51.80;

-- 3.2 Desligar del préstamo los gastos de seguro (solo si el grep del código confirma que no se usa para el seguro). Esperado: 6 filas.
update public.transactions
   set loan_id = null
 where loan_id = '2d70a5bc-7c7f-404b-9cad-9f4a24fa902a' and description ilike 'SEGURO MINI%';

-- 3.3 Añadir el seguro de febrero (BBVA 02/03/2026, V). Esperado: 1 transacción, 2 apuntes.
with t as (
  insert into public.transactions (date, description, user_id)
  select '2026-03-02', 'SEGURO MINI', 'a6fd07ad-06e4-41cb-8226-0747c24a6543'::uuid
   where not exists (select 1 from public.transactions
                      where date = '2026-03-02' and description ilike 'SEGURO MINI%')
  returning id
)
insert into public.journal_entries (transaction_id, account_id, amount, memo, user_id)
select t.id, (select id from public.accounts where code = '1000'), -51.80, 'SEGURO MINI', 'a6fd07ad-06e4-41cb-8226-0747c24a6543'::uuid from t
union all
select t.id, (select id from public.accounts where code = '5009-1'), 51.80, 'SEGURO MINI', 'a6fd07ad-06e4-41cb-8226-0747c24a6543'::uuid from t;

-- ============ BLOQUE 4 · THERMOMIX (Cofidis) ============
-- 1.492,47 - 20 x 31,10 = 870,47 (20 cuotas en loan_payments; la de noviembre es R, sin extracto). Esperado: 1 fila.
update public.loans
   set remaining_amount = 870.47, estado_dato = 'calculado'
 where id = 'e9c7025f-9dd9-4b91-864a-8f2486aeb019';

-- ============ BLOQUE 5 · Recurrente de 244 € ============
-- La hucha se hace a mano el día de cobro. Esperado: 1 fila.
update public.recurring_transactions
   set active = false
 where id = 'b769fcc2-7d9f-45f3-8fd8-8c7cd84a31d9';

-- ============ BLOQUE 6 · Saldos reportados 12/11/2026 ============
-- Supuesto: colchón 1.392,48 (Revolut) y Abogado 786,51. Esperado: 4 filas.
update public.subcuentas set saldo = 1392.48, ultima_actualizacion = now(), estado_dato = 'reportado'
 where id = '2a83734e-ece0-4e4a-9f36-8559d723629c';   -- Colchón de emergencia
update public.subcuentas set saldo = 786.51,  ultima_actualizacion = now(), estado_dato = 'reportado'
 where id = 'c6092481-695b-4d13-bd47-579bbf0a5fdf';   -- Reserva Abogado
update public.subcuentas set saldo = 0.00,    ultima_actualizacion = now(), estado_dato = 'reportado'
 where id = 'e1ba9a14-debc-4e98-9c06-eb5a59c43c41';   -- Reserva amortización BBVA NUEVO
update public.subcuentas set saldo = 668.98,  estado_dato = 'reportado'
 where id = '303bf4e5-fa9c-47e3-9888-6448326eb524';   -- Cuenta corriente (ya estaba en 668,98)

-- ============ BLOQUE 7 · COMPROBACIÓN FINAL (solo lectura) ============
select 'compromisos Caso 1 pendientes' as chequeo, descripcion, importe, pagado, fecha, transaction_id
  from public.compromisos where id in ('cdc45665-8557-429a-a825-3a20038f28ab','36254cd0-9912-4432-993b-d0f9ec1c66f6');
select 'tx 30/10' as chequeo, t.description, a.code, je.amount
  from public.transactions t join public.journal_entries je on je.transaction_id = t.id
  join public.accounts a on a.id = je.account_id where t.date = '2026-10-30' order by t.description, je.amount;
select 'loan_payments MINI 51,80 (debe ser 0)' as chequeo, count(*) from public.loan_payments
  where loan_id = '2d70a5bc-7c7f-404b-9cad-9f4a24fa902a' and amount = 51.80;
select 'SEGURO MINI por mes' as chequeo, date, amount from public.transactions t
  join public.journal_entries je on je.transaction_id = t.id join public.accounts a on a.id = je.account_id
  where a.code = '5009-1' order by date;
select 'subcuentas' as chequeo, nombre, saldo, estado_dato from public.subcuentas order by nombre;
select 'recurrente 244 (debe ser false)' as chequeo, active from public.recurring_transactions
  where id = 'b769fcc2-7d9f-45f3-8fd8-8c7cd84a31d9';
