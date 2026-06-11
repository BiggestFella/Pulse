-- BAK-27: catalog additions on top of 0005 (history-import follow-up).
-- New variations, the Standing Curl exercise, and the High Row Machine rename.
-- Idempotent (ON CONFLICT / id-keyed UPDATEs); safe on the already-seeded dev DB.

-- 1. Rename High Row Machine -> High Row; its 'Standard' variation -> 'Machine'.
update exercises  set name = 'High Row' where id = '8283d688-8681-5459-91a8-8ed5db3dc4a5';
update variations set name = 'Machine'  where id = '9501e93b-54b7-52c1-875a-853190a44416';

-- 2. New exercise: Standing Curl (Biceps).
insert into exercises (id, name, muscle_group) values
  ('bc9d1306-8fbe-563c-89eb-507ac516993d', 'Standing Curl', 'Biceps')
on conflict (id) do nothing;

-- 3. New variations (incl. Standing Curl's and High Row / Dumbbells).
insert into variations (id, exercise_id, name, equipment) values
  ('db64e07c-ef81-5fb0-90dc-34f69fba9823', 'ba11b697-5f0a-4c8c-ab39-37669ec0d154', 'DBs'         , 'Dumbbells'),
  ('4b9ca1b8-ec62-5085-be5e-e74dea26348b', '0f302802-8a25-5d50-9a01-f2443a97ab6b', 'DBs'         , 'Dumbbells'),
  ('5d80945e-a02a-5fbd-81bc-98086672d50c', '0bca9820-ee3b-5e99-be5b-2086c1aca31a', 'High-to-Low' , 'Cable'),
  ('d17966b5-5a81-5a25-a837-c033bed765ca', '0bca9820-ee3b-5e99-be5b-2086c1aca31a', 'Incline'     , 'Cable'),
  ('6cba5f72-3e31-5c7a-ab77-cecc9549024e', '701d981d-d69e-50b1-ab64-ebd02ff6839f', 'Wide Grip'   , 'Cable'),
  ('2fe9381b-4ac7-521c-b55f-7f3bfb738700', '701d981d-d69e-50b1-ab64-ebd02ff6839f', 'Single Arm'  , 'Cable'),
  ('3874e66d-47e8-5a27-bca8-67af0b38b496', '8283d688-8681-5459-91a8-8ed5db3dc4a5', 'Dumbbells'   , 'Dumbbells'),
  ('bc43a620-3ac3-54dd-bcd5-9972e0512c06', 'bc9d1306-8fbe-563c-89eb-507ac516993d', 'Machine'     , 'Machine'),
  ('1e03763e-f81f-53b7-8d8b-0c251d3cc26b', 'bc9d1306-8fbe-563c-89eb-507ac516993d', 'DBs'         , 'Dumbbells'),
  ('93941c65-52d2-5bfc-9d03-030bd985d83d', 'bc9d1306-8fbe-563c-89eb-507ac516993d', 'EZ Bar'      , 'EZ Bar')
on conflict (id) do nothing;

-- 4. Default variation for the new Standing Curl exercise = Machine.
update exercises set default_variation_id = 'bc43a620-3ac3-54dd-bcd5-9972e0512c06' where id = 'bc9d1306-8fbe-563c-89eb-507ac516993d';
