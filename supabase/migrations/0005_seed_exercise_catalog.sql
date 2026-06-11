-- BAK-27: seed the authoritative exercise catalog (parents + variations).
-- Global, read-only catalog shared by all users (RLS read policies in 0002).
-- Reuses the fixed UUIDs that seed_dev.sql / TodaysWorkout.swift depend on so
-- existing references keep resolving. ON CONFLICT DO NOTHING makes this safe to
-- apply on top of an already-partially-seeded dev database.
-- 48 exercises, 101 variations.

-- ── parent exercises ────────────────────────────────────────────────────────
insert into exercises (id, name, muscle_group) values
  ('af17a626-0d98-50e1-896b-72061ad71bc0', 'Leg Extension'                   , 'Legs'),
  ('bd6c9cd0-92de-5a5a-a7d0-cabfdcb20b27', 'Leg Press'                       , 'Legs'),
  ('84faa26c-16f2-54e6-b15f-15fda6490dcd', 'Calf Raise'                      , 'Legs'),
  ('2ad6059b-7174-5577-89b1-a411dee4e044', 'Smith Squat'                     , 'Legs'),
  ('771938b6-62ea-55fa-80e2-a34ade3558ed', 'Hack Squat'                      , 'Legs'),
  ('bf2733fd-03ce-55a5-8525-842d5e914206', 'Split Squat'                     , 'Legs'),
  ('0f302802-8a25-5d50-9a01-f2443a97ab6b', 'Walking Lunge'                   , 'Legs'),
  ('31c73516-22ef-5dd8-b5d5-e720f544ae0f', 'Romanian Deadlift'               , 'Legs'),
  ('20b47e68-9067-544c-9215-d6c17c5e8b07', 'Hip Thrust'                      , 'Legs'),
  ('395bdaf2-32f9-5bd6-9e10-52a680c65467', 'Glute Bridge'                    , 'Legs'),
  ('a2ed8c67-645e-5a50-a6fd-9017525ffdf5', 'Leg Curl'                        , 'Legs'),
  ('8bb4e20e-3e84-57d5-9986-f5e707c6c676', 'Hip Adduction Machine'           , 'Legs'),
  ('99ed8dc8-f53c-547c-a530-d6b73dbf6fb3', 'Hip Abduction Machine'           , 'Legs'),
  ('eeae5b67-e5be-5399-b510-91dcd0472628', 'Flat Chest Press'                , 'Chest'),
  ('59d41db7-85fc-4749-9347-e14d086f18f5', 'Incline Chest Press'             , 'Chest'),
  ('93fc988d-f1e3-5e86-8926-35bab0d42e8a', 'Decline Chest Press'             , 'Chest'),
  ('219e4a05-f417-5264-9808-0d45521e2e27', 'Close Grip Chest Press'          , 'Chest'),
  ('d87769e4-6c75-5882-bc7a-3a737ddc755c', 'Pec Deck Fly'                    , 'Chest'),
  ('0bca9820-ee3b-5e99-be5b-2086c1aca31a', 'Cable Crossover'                 , 'Chest'),
  ('2a0236e6-a32e-5700-8039-b8995551442d', 'Chest Dip'                       , 'Chest'),
  ('d23e3b5d-9c0f-460a-8cad-f28271f26280', 'Push-Up'                         , 'Chest'),
  ('ba11b697-5f0a-4c8c-ab39-37669ec0d154', 'Shoulder Press'                  , 'Shoulders'),
  ('170fbbf9-3df0-55bc-a922-670a29ea4c0e', 'Lateral Raise'                   , 'Shoulders'),
  ('998e31de-7d0d-5c61-8eff-61f68e2d261f', 'Rear Delt Swing'                 , 'Shoulders'),
  ('e548a9ea-5dae-5fe4-b2e1-5340ec5f9711', 'Front Raise'                     , 'Shoulders'),
  ('30ff4dba-6e0f-4b5d-b9cf-1acd2ed0b755', 'Tricep Extension'                , 'Triceps'),
  ('4dd5a77d-9a77-561d-8cb3-fd94b6269425', 'Tricep Pushdown'                 , 'Triceps'),
  ('233840be-3bb0-5fda-a647-42bbf293a341', 'Overhead Tricep Cable Extension' , 'Triceps'),
  ('1958ad91-4391-5c76-8684-f990d5333690', 'Tricep Dip'                      , 'Triceps'),
  ('64c93a0f-4a13-5904-ade3-870b7acecafe', 'Tricep Kickback'                 , 'Triceps'),
  ('ad971ed1-7ebe-40e9-99bb-47d404020037', 'Lat Pulldown'                    , 'Back'),
  ('701d981d-d69e-50b1-ab64-ebd02ff6839f', 'Seated Cable Row'                , 'Back'),
  ('864e6f2a-9ae2-5973-adaf-33be40fad26a', 'Chest Supported Row'             , 'Back'),
  ('a264fce8-5f62-5a9e-baf7-945f27a1d94b', 'Seated Machine Row'              , 'Back'),
  ('4d355a01-38b6-5b09-811f-38953f927648', 'T Bar Row'                       , 'Back'),
  ('f33eabe7-902e-54ec-b8f0-825aef3dbd19', 'Bent Over Row'                   , 'Back'),
  ('8283d688-8681-5459-91a8-8ed5db3dc4a5', 'High Row Machine'                , 'Back'),
  ('80dcb624-4ce9-5734-b692-43950897f2e0', 'Straight-Arm Pulldown'           , 'Back'),
  ('ebb66e5b-cad9-5bb6-8328-6704f9185ef2', 'Pull-Up'                         , 'Back'),
  ('51796dba-51ed-5dba-a180-a247815fcce7', 'Shrug'                           , 'Back'),
  ('1b15e740-6496-5756-919c-ee204447f564', 'Back Extension'                  , 'Back'),
  ('63eeda9c-cc67-59a5-aea4-e1905771ad43', 'DB Curl'                         , 'Biceps'),
  ('fa1b32d9-b984-542b-843a-1ceaeecacd79', 'Hammer Curl'                     , 'Biceps'),
  ('1b6e5da3-39d0-5b0b-8cd8-55c53e6497cd', 'EZ Bar Curl'                     , 'Biceps'),
  ('2c796f45-cea6-5c1e-87a0-0a3e6b35c8ab', 'Cable Bar Curl'                  , 'Biceps'),
  ('908a7e05-0635-4aaf-8de7-5a9eed2e91f9', 'Preacher Curl'                   , 'Biceps'),
  ('1aafd3da-bba6-55de-b050-0fbcceb61167', 'Spider Curl'                     , 'Biceps'),
  ('cf07b6a4-7854-5ede-a289-629253b759a6', 'Farmer Carry'                    , 'Other')
on conflict (id) do nothing;

-- ── variations ──────────────────────────────────────────────────────────────
insert into variations (id, exercise_id, name, equipment) values
  ('0b7b7d30-2e84-5861-b6d2-d3da6b08d5c2', 'af17a626-0d98-50e1-896b-72061ad71bc0', 'Standard'            , 'Machine'),
  ('59037384-68e6-53ef-8033-6e1dba5a627d', 'af17a626-0d98-50e1-896b-72061ad71bc0', 'Lengthened'          , 'Machine'),
  ('d19dfb94-d7cc-53b4-b587-c37dca37e617', 'af17a626-0d98-50e1-896b-72061ad71bc0', 'Single Leg'          , 'Machine'),
  ('cba5c909-9815-5f7c-b2d9-d00dab0f9c34', 'bd6c9cd0-92de-5a5a-a7d0-cabfdcb20b27', 'Mid Stance'          , 'Machine'),
  ('b8ec9f82-270d-5e24-bcb7-f35bb21d8ef2', 'bd6c9cd0-92de-5a5a-a7d0-cabfdcb20b27', 'Wide Stance'         , 'Machine'),
  ('a53f3d5f-f871-52cc-aa81-1fc716fc0dc5', 'bd6c9cd0-92de-5a5a-a7d0-cabfdcb20b27', 'Narrow Stance'       , 'Machine'),
  ('4f274646-19b6-5cab-9a09-b3620bb88e55', '84faa26c-16f2-54e6-b15f-15fda6490dcd', 'Standing'            , 'Machine'),
  ('53c50c4b-9cfd-5232-bd25-63ebb271fb1c', '84faa26c-16f2-54e6-b15f-15fda6490dcd', 'Seated'              , 'Machine'),
  ('934adfe2-093f-589e-a573-c06a6d7ff4ce', '84faa26c-16f2-54e6-b15f-15fda6490dcd', 'Leg Press'           , 'Machine'),
  ('020ee579-f228-5007-ad1e-2b135e2fb771', '2ad6059b-7174-5577-89b1-a411dee4e044', 'Standard'            , 'Smith Machine'),
  ('22aa4dd4-2068-5918-993e-436b3a162e8a', '771938b6-62ea-55fa-80e2-a34ade3558ed', 'Standard'            , 'Machine'),
  ('f0121723-1317-566f-a196-b817948857cc', 'bf2733fd-03ce-55a5-8525-842d5e914206', 'Smith Machine'       , 'Smith Machine'),
  ('3cc23135-b73f-5dd1-8324-f62fd3e06f40', 'bf2733fd-03ce-55a5-8525-842d5e914206', 'DBs'                 , 'Dumbbells'),
  ('fef1f4c3-0db7-59cc-bd03-54e7532b1563', '0f302802-8a25-5d50-9a01-f2443a97ab6b', 'Bodyweight'          , 'Bodyweight'),
  ('91dcd22d-4272-5779-ac2b-141b84701261', '31c73516-22ef-5dd8-b5d5-e720f544ae0f', 'DBs'                 , 'Dumbbells'),
  ('05b9721a-e3cc-54f6-892a-398273b7544e', '31c73516-22ef-5dd8-b5d5-e720f544ae0f', 'Smith'               , 'Smith Machine'),
  ('344eeef0-72f9-5eeb-8220-ff5791884abb', '31c73516-22ef-5dd8-b5d5-e720f544ae0f', 'Barbell'             , 'Barbell'),
  ('1ef39ecc-aae3-5740-8be9-e16eefaa5c91', '20b47e68-9067-544c-9215-d6c17c5e8b07', 'Standard'            , 'Barbell'),
  ('73df6983-03f8-5e4c-b446-bc8e7334756c', '395bdaf2-32f9-5bd6-9e10-52a680c65467', 'Standard'            , 'Barbell'),
  ('5c41a9c9-aff0-56af-a6d5-5192a9814c4d', 'a2ed8c67-645e-5a50-a6fd-9017525ffdf5', 'Machine'             , 'Machine'),
  ('e5fdea34-6096-5a24-a839-5a013e7855a7', '8bb4e20e-3e84-57d5-9986-f5e707c6c676', 'Standard'            , 'Machine'),
  ('ec155f47-f196-53cb-8119-0c91959938f7', '99ed8dc8-f53c-547c-a530-d6b73dbf6fb3', 'Standard'            , 'Machine'),
  ('c864cf4b-dc9b-591d-9206-c48632292138', 'eeae5b67-e5be-5399-b510-91dcd0472628', 'Machine'             , 'Machine'),
  ('feb12112-bbd2-5429-887b-74c6af6e4364', 'eeae5b67-e5be-5399-b510-91dcd0472628', 'Single Arm Machine'  , 'Machine'),
  ('cd81fa63-eef0-568e-9559-d0441e22ee62', 'eeae5b67-e5be-5399-b510-91dcd0472628', 'DBs'                 , 'Dumbbells'),
  ('2cd32af4-a561-59ce-90b9-136314bcc74d', 'eeae5b67-e5be-5399-b510-91dcd0472628', 'Smith Machine'       , 'Smith Machine'),
  ('9ff89e87-1936-55ad-8860-f97c28e58f04', 'eeae5b67-e5be-5399-b510-91dcd0472628', 'Barbell'             , 'Barbell'),
  ('9e0a0249-ebab-5745-a3fc-584432763876', 'eeae5b67-e5be-5399-b510-91dcd0472628', 'Hammer Strength'     , 'Hammer Strength'),
  ('fd5c570e-ce52-5ba8-95f7-a5444c1545be', '59d41db7-85fc-4749-9347-e14d086f18f5', 'DBs'                 , 'Dumbbells'),
  ('ce0e5e04-94d9-4adb-9b42-635faf5a191d', '59d41db7-85fc-4749-9347-e14d086f18f5', 'Machine'             , 'Machine'),
  ('19a7fd2f-5763-5922-a67a-2caf866a9bc9', '59d41db7-85fc-4749-9347-e14d086f18f5', 'Smith'               , 'Smith Machine'),
  ('f5779735-aa49-5b01-b935-1fb7cf02fafc', '59d41db7-85fc-4749-9347-e14d086f18f5', 'Cable'               , 'Cable'),
  ('151300fe-ecba-5b1e-bf81-5fcf31c25558', '59d41db7-85fc-4749-9347-e14d086f18f5', 'Barbell'             , 'Barbell'),
  ('47488ecf-d7ef-5c7f-ab0c-e15af4c36aac', '93fc988d-f1e3-5e86-8926-35bab0d42e8a', 'Machine'             , 'Machine'),
  ('b5edd3b3-fece-5ebf-9426-261755a7289a', '93fc988d-f1e3-5e86-8926-35bab0d42e8a', 'Single Arm Machine'  , 'Machine'),
  ('10f6ae9d-9d1e-59d1-8700-63864a0fa413', '219e4a05-f417-5264-9808-0d45521e2e27', 'DBs'                 , 'Dumbbells'),
  ('4b047cea-b445-5052-85db-8dced4b8f5dc', 'd87769e4-6c75-5882-bc7a-3a737ddc755c', 'Standard'            , 'Machine'),
  ('e4d4184d-f6e3-51c0-bf4a-7d305a77f020', '0bca9820-ee3b-5e99-be5b-2086c1aca31a', 'Standard'            , 'Cable'),
  ('823b80ca-1fbe-579b-bd1b-5f77620b7614', '2a0236e6-a32e-5700-8039-b8995551442d', 'Standard'            , 'Bodyweight'),
  ('f4861f10-fed5-5cd2-920d-ddd3f989ef5e', 'd23e3b5d-9c0f-460a-8cad-f28271f26280', 'Standard'            , 'Bodyweight'),
  ('d9dae16f-24d2-4c9d-8a92-a710d0a9ae6f', 'd23e3b5d-9c0f-460a-8cad-f28271f26280', 'Deficit'             , 'Bodyweight'),
  ('995474ff-b87f-54cd-9b8c-894704472e8b', 'd23e3b5d-9c0f-460a-8cad-f28271f26280', 'Tricep'              , 'Bodyweight'),
  ('c2229eca-465f-426e-91b6-af426eef76ba', 'ba11b697-5f0a-4c8c-ab39-37669ec0d154', 'Seated Machine'      , 'Machine'),
  ('e2d651ba-6dc8-50a0-93e1-c296870f9cdd', 'ba11b697-5f0a-4c8c-ab39-37669ec0d154', 'Standing Machine'    , 'Machine'),
  ('81009f30-c173-5f33-a080-ec420582f97e', '170fbbf9-3df0-55bc-a922-670a29ea4c0e', 'DBs'                 , 'Dumbbells'),
  ('cfcc1824-b15b-578a-8609-fd40a9333259', '170fbbf9-3df0-55bc-a922-670a29ea4c0e', 'Single Arm Cable'    , 'Cable'),
  ('a34ae3b9-cf0f-5e62-ab29-60b8a119d9bd', '170fbbf9-3df0-55bc-a922-670a29ea4c0e', 'Seated Machine'      , 'Machine'),
  ('2a2cd268-efab-5bfb-b03c-96c1784e4f8d', '170fbbf9-3df0-55bc-a922-670a29ea4c0e', 'Seated Pulse'        , 'Dumbbells'),
  ('e5d77c18-9edf-5234-ab47-9a373b9ca8c0', '170fbbf9-3df0-55bc-a922-670a29ea4c0e', 'Standing Machine'    , 'Machine'),
  ('39409d09-b176-5f08-b1c4-1606a9cda8d0', '998e31de-7d0d-5c61-8eff-61f68e2d261f', 'DBs'                 , 'Dumbbells'),
  ('61d9352b-e688-559d-a624-4340ea9e4ce5', 'e548a9ea-5dae-5fe4-b2e1-5340ec5f9711', 'DBs'                 , 'Dumbbells'),
  ('d7375a01-ad26-5147-8c8a-9232ca47e939', 'e548a9ea-5dae-5fe4-b2e1-5340ec5f9711', 'Rope Cable'          , 'Cable'),
  ('be78fd0c-1cf4-5a5f-8c3e-3f587ef398ea', '30ff4dba-6e0f-4b5d-b9cf-1acd2ed0b755', 'Machine'             , 'Machine'),
  ('df09d6b3-30b4-5b11-9888-525ae8a665da', '30ff4dba-6e0f-4b5d-b9cf-1acd2ed0b755', 'Rope'                , 'Cable'),
  ('89553dae-bcaf-4031-9821-a7e4fd5d1e0e', '30ff4dba-6e0f-4b5d-b9cf-1acd2ed0b755', 'Plate Loaded'        , 'Plate Loaded'),
  ('b106bd34-0df5-563c-88f1-100f73a68f76', '30ff4dba-6e0f-4b5d-b9cf-1acd2ed0b755', 'Cable Bar'           , 'Cable'),
  ('e627f315-8730-5cb3-a457-bdaf3169a68a', '4dd5a77d-9a77-561d-8cb3-fd94b6269425', 'Rope Cross'          , 'Cable'),
  ('8adb7a43-a37b-5114-859d-9b7cb8d7ecdf', '4dd5a77d-9a77-561d-8cb3-fd94b6269425', 'Underhand Bar'       , 'Cable'),
  ('a7bfb127-4303-5066-acb4-e2660977e6af', '4dd5a77d-9a77-561d-8cb3-fd94b6269425', 'Single Arm'          , 'Cable'),
  ('8f5b33a1-b43c-5e56-9846-1187072c2d97', '233840be-3bb0-5fda-a647-42bbf293a341', 'Rope'                , 'Cable'),
  ('aecf827e-6c81-5028-a373-09c20aabb3f5', '1958ad91-4391-5c76-8684-f990d5333690', 'Standard'            , 'Bodyweight'),
  ('b6da3170-32e6-5447-8140-a0f89860a557', '64c93a0f-4a13-5904-ade3-870b7acecafe', 'DBs'                 , 'Dumbbells'),
  ('cbbb3cff-0ade-4c81-b31c-c74f8530aac9', 'ad971ed1-7ebe-40e9-99bb-47d404020037', 'D-bar'               , 'Cable'),
  ('4b094db6-128d-5797-8eb8-801032cb90bf', 'ad971ed1-7ebe-40e9-99bb-47d404020037', 'Neutral Grip'        , 'Cable'),
  ('5a40ae24-2eef-5d7d-880f-83a1f34ae587', 'ad971ed1-7ebe-40e9-99bb-47d404020037', 'Wide Grip'           , 'Cable'),
  ('8f945bc4-acc1-5707-b789-95f891f4ee1a', 'ad971ed1-7ebe-40e9-99bb-47d404020037', 'Machine'             , 'Machine'),
  ('4a8e6678-b48a-529d-aea2-6764852e6958', '701d981d-d69e-50b1-ab64-ebd02ff6839f', 'Standard'            , 'Cable'),
  ('886e2b7e-53a4-5421-80b0-53de9ec5bddb', '701d981d-d69e-50b1-ab64-ebd02ff6839f', 'High-to-Low'         , 'Cable'),
  ('b7934423-393a-55d8-a25a-dd68dbdae8c6', '864e6f2a-9ae2-5973-adaf-33be40fad26a', 'Standard'            , 'Machine'),
  ('66e19197-e132-56bb-bb13-90389b2679f6', 'a264fce8-5f62-5a9e-baf7-945f27a1d94b', 'Wide Grip'           , 'Machine'),
  ('d84c08cf-24f2-5042-aa37-7021f59da59b', 'a264fce8-5f62-5a9e-baf7-945f27a1d94b', 'Single Arm'          , 'Machine'),
  ('7ccc19ce-77b1-5d21-9a03-cff87b9ec977', '4d355a01-38b6-5b09-811f-38953f927648', 'Standard'            , 'T Bar'),
  ('f47caf37-112d-5dcd-a693-f7d7770e070f', 'f33eabe7-902e-54ec-b8f0-825aef3dbd19', 'DBs'                 , 'Dumbbells'),
  ('3dbd1c62-e449-56fe-82ce-e7e8083ab514', 'f33eabe7-902e-54ec-b8f0-825aef3dbd19', 'Single DB'           , 'Dumbbell'),
  ('9501e93b-54b7-52c1-875a-853190a44416', '8283d688-8681-5459-91a8-8ed5db3dc4a5', 'Standard'            , 'Machine'),
  ('f95bdff0-d80a-5535-b315-bd3e69f3d698', '80dcb624-4ce9-5734-b692-43950897f2e0', 'Rope'                , 'Cable'),
  ('bbaa7d0e-7333-5ed8-93d7-ec71e62aa5a5', 'ebb66e5b-cad9-5bb6-8328-6704f9185ef2', 'Standard'            , 'Bodyweight'),
  ('743f89e9-7faa-5dc1-9328-36cdf0b7d02f', 'ebb66e5b-cad9-5bb6-8328-6704f9185ef2', 'Chin-Up'             , 'Bodyweight'),
  ('2f4ef272-0123-55b6-80d4-7127e5f89c64', 'ebb66e5b-cad9-5bb6-8328-6704f9185ef2', 'Close Grip'          , 'Bodyweight'),
  ('6a5059a7-c2ce-567c-910e-5be4cf93c410', '51796dba-51ed-5dba-a180-a247815fcce7', 'Standing'            , 'Barbell'),
  ('997af244-e154-51ef-b805-6f911b10fdcb', '51796dba-51ed-5dba-a180-a247815fcce7', 'Seated'              , 'Dumbbells'),
  ('286603e9-ea7a-5384-9d9d-d2c455f5a9f3', '51796dba-51ed-5dba-a180-a247815fcce7', 'Machine'             , 'Machine'),
  ('7d36fec2-8ed6-5592-bca6-c02ed2a4e3f7', '1b15e740-6496-5756-919c-ee204447f564', 'Standard'            , 'Bodyweight'),
  ('69d706ad-d1b8-5f90-8808-f2788742ba2f', '1b15e740-6496-5756-919c-ee204447f564', 'Machine'             , 'Machine'),
  ('e897f9a4-f6da-5cf1-ab59-95631fd5240f', '63eeda9c-cc67-59a5-aea4-e1905771ad43', 'Seated'              , 'Dumbbells'),
  ('f3bf172d-fb8a-5838-8a53-fc5a8d4824b4', '63eeda9c-cc67-59a5-aea4-e1905771ad43', 'Incline'             , 'Dumbbells'),
  ('a018c57e-2424-5799-b981-462f60573785', '63eeda9c-cc67-59a5-aea4-e1905771ad43', 'Outside Elbow'       , 'Dumbbells'),
  ('65df86ac-9daa-57fe-873e-98ff95c42575', '63eeda9c-cc67-59a5-aea4-e1905771ad43', 'Bent Over Single'    , 'Dumbbell'),
  ('54b70526-d339-52c7-9b58-6994994a34a7', 'fa1b32d9-b984-542b-843a-1ceaeecacd79', 'DBs'                 , 'Dumbbells'),
  ('52ad8c9a-a3ba-5805-b007-23364ce93207', 'fa1b32d9-b984-542b-843a-1ceaeecacd79', 'Cable Rope'          , 'Cable'),
  ('17953199-99e3-5c80-acf4-3984153c255c', '1b6e5da3-39d0-5b0b-8cd8-55c53e6497cd', 'Standard'            , 'EZ Bar'),
  ('411c390b-5a40-5dae-aacf-58f5dee1c8a0', '1b6e5da3-39d0-5b0b-8cd8-55c53e6497cd', 'Reverse Grip'        , 'EZ Bar'),
  ('f82f7001-7d55-54d4-9ab5-82ae6b9ba3b2', '1b6e5da3-39d0-5b0b-8cd8-55c53e6497cd', 'Drag'                , 'EZ Bar'),
  ('fd6b4897-173c-5cdf-9fc9-26841dabb444', '2c796f45-cea6-5c1e-87a0-0a3e6b35c8ab', 'Standard'            , 'Cable'),
  ('c556dccf-6547-542d-bd92-e840fb512b10', '2c796f45-cea6-5c1e-87a0-0a3e6b35c8ab', 'Double Cable'        , 'Cable'),
  ('6e61a13c-ff15-5779-b9f6-3b65c973d2a2', '2c796f45-cea6-5c1e-87a0-0a3e6b35c8ab', 'Drag'                , 'Cable'),
  ('6342839f-3025-405c-977a-da849d1b1083', '908a7e05-0635-4aaf-8de7-5a9eed2e91f9', 'Machine'             , 'Machine'),
  ('fb81d9ad-aeb6-5237-9c12-7cd3777dd734', '908a7e05-0635-4aaf-8de7-5a9eed2e91f9', 'Hammer Grip Machine' , 'Machine'),
  ('5a7e59ec-0089-5886-8db7-f1161fc840f4', '908a7e05-0635-4aaf-8de7-5a9eed2e91f9', 'EZ Bar'              , 'EZ Bar'),
  ('46c66bf8-d87b-52da-9238-7e301d024b7a', '1aafd3da-bba6-55de-b050-0fbcceb61167', 'Standard'            , 'Dumbbells'),
  ('92d26f98-ce13-54de-a066-6818b2fd4bb7', 'cf07b6a4-7854-5ede-a289-629253b759a6', 'Standard'            , 'Dumbbells')
on conflict (id) do nothing;

-- ── default variation per exercise ──────────────────────────────────────────
update exercises set default_variation_id = '0b7b7d30-2e84-5861-b6d2-d3da6b08d5c2' where id = 'af17a626-0d98-50e1-896b-72061ad71bc0';
update exercises set default_variation_id = 'cba5c909-9815-5f7c-b2d9-d00dab0f9c34' where id = 'bd6c9cd0-92de-5a5a-a7d0-cabfdcb20b27';
update exercises set default_variation_id = '4f274646-19b6-5cab-9a09-b3620bb88e55' where id = '84faa26c-16f2-54e6-b15f-15fda6490dcd';
update exercises set default_variation_id = '020ee579-f228-5007-ad1e-2b135e2fb771' where id = '2ad6059b-7174-5577-89b1-a411dee4e044';
update exercises set default_variation_id = '22aa4dd4-2068-5918-993e-436b3a162e8a' where id = '771938b6-62ea-55fa-80e2-a34ade3558ed';
update exercises set default_variation_id = 'f0121723-1317-566f-a196-b817948857cc' where id = 'bf2733fd-03ce-55a5-8525-842d5e914206';
update exercises set default_variation_id = 'fef1f4c3-0db7-59cc-bd03-54e7532b1563' where id = '0f302802-8a25-5d50-9a01-f2443a97ab6b';
update exercises set default_variation_id = '91dcd22d-4272-5779-ac2b-141b84701261' where id = '31c73516-22ef-5dd8-b5d5-e720f544ae0f';
update exercises set default_variation_id = '1ef39ecc-aae3-5740-8be9-e16eefaa5c91' where id = '20b47e68-9067-544c-9215-d6c17c5e8b07';
update exercises set default_variation_id = '73df6983-03f8-5e4c-b446-bc8e7334756c' where id = '395bdaf2-32f9-5bd6-9e10-52a680c65467';
update exercises set default_variation_id = '5c41a9c9-aff0-56af-a6d5-5192a9814c4d' where id = 'a2ed8c67-645e-5a50-a6fd-9017525ffdf5';
update exercises set default_variation_id = 'e5fdea34-6096-5a24-a839-5a013e7855a7' where id = '8bb4e20e-3e84-57d5-9986-f5e707c6c676';
update exercises set default_variation_id = 'ec155f47-f196-53cb-8119-0c91959938f7' where id = '99ed8dc8-f53c-547c-a530-d6b73dbf6fb3';
update exercises set default_variation_id = 'c864cf4b-dc9b-591d-9206-c48632292138' where id = 'eeae5b67-e5be-5399-b510-91dcd0472628';
update exercises set default_variation_id = 'fd5c570e-ce52-5ba8-95f7-a5444c1545be' where id = '59d41db7-85fc-4749-9347-e14d086f18f5';
update exercises set default_variation_id = '47488ecf-d7ef-5c7f-ab0c-e15af4c36aac' where id = '93fc988d-f1e3-5e86-8926-35bab0d42e8a';
update exercises set default_variation_id = '10f6ae9d-9d1e-59d1-8700-63864a0fa413' where id = '219e4a05-f417-5264-9808-0d45521e2e27';
update exercises set default_variation_id = '4b047cea-b445-5052-85db-8dced4b8f5dc' where id = 'd87769e4-6c75-5882-bc7a-3a737ddc755c';
update exercises set default_variation_id = 'e4d4184d-f6e3-51c0-bf4a-7d305a77f020' where id = '0bca9820-ee3b-5e99-be5b-2086c1aca31a';
update exercises set default_variation_id = '823b80ca-1fbe-579b-bd1b-5f77620b7614' where id = '2a0236e6-a32e-5700-8039-b8995551442d';
update exercises set default_variation_id = 'f4861f10-fed5-5cd2-920d-ddd3f989ef5e' where id = 'd23e3b5d-9c0f-460a-8cad-f28271f26280';
update exercises set default_variation_id = 'c2229eca-465f-426e-91b6-af426eef76ba' where id = 'ba11b697-5f0a-4c8c-ab39-37669ec0d154';
update exercises set default_variation_id = '81009f30-c173-5f33-a080-ec420582f97e' where id = '170fbbf9-3df0-55bc-a922-670a29ea4c0e';
update exercises set default_variation_id = '39409d09-b176-5f08-b1c4-1606a9cda8d0' where id = '998e31de-7d0d-5c61-8eff-61f68e2d261f';
update exercises set default_variation_id = '61d9352b-e688-559d-a624-4340ea9e4ce5' where id = 'e548a9ea-5dae-5fe4-b2e1-5340ec5f9711';
update exercises set default_variation_id = 'be78fd0c-1cf4-5a5f-8c3e-3f587ef398ea' where id = '30ff4dba-6e0f-4b5d-b9cf-1acd2ed0b755';
update exercises set default_variation_id = 'e627f315-8730-5cb3-a457-bdaf3169a68a' where id = '4dd5a77d-9a77-561d-8cb3-fd94b6269425';
update exercises set default_variation_id = '8f5b33a1-b43c-5e56-9846-1187072c2d97' where id = '233840be-3bb0-5fda-a647-42bbf293a341';
update exercises set default_variation_id = 'aecf827e-6c81-5028-a373-09c20aabb3f5' where id = '1958ad91-4391-5c76-8684-f990d5333690';
update exercises set default_variation_id = 'b6da3170-32e6-5447-8140-a0f89860a557' where id = '64c93a0f-4a13-5904-ade3-870b7acecafe';
update exercises set default_variation_id = 'cbbb3cff-0ade-4c81-b31c-c74f8530aac9' where id = 'ad971ed1-7ebe-40e9-99bb-47d404020037';
update exercises set default_variation_id = '4a8e6678-b48a-529d-aea2-6764852e6958' where id = '701d981d-d69e-50b1-ab64-ebd02ff6839f';
update exercises set default_variation_id = 'b7934423-393a-55d8-a25a-dd68dbdae8c6' where id = '864e6f2a-9ae2-5973-adaf-33be40fad26a';
update exercises set default_variation_id = '66e19197-e132-56bb-bb13-90389b2679f6' where id = 'a264fce8-5f62-5a9e-baf7-945f27a1d94b';
update exercises set default_variation_id = '7ccc19ce-77b1-5d21-9a03-cff87b9ec977' where id = '4d355a01-38b6-5b09-811f-38953f927648';
update exercises set default_variation_id = 'f47caf37-112d-5dcd-a693-f7d7770e070f' where id = 'f33eabe7-902e-54ec-b8f0-825aef3dbd19';
update exercises set default_variation_id = '9501e93b-54b7-52c1-875a-853190a44416' where id = '8283d688-8681-5459-91a8-8ed5db3dc4a5';
update exercises set default_variation_id = 'f95bdff0-d80a-5535-b315-bd3e69f3d698' where id = '80dcb624-4ce9-5734-b692-43950897f2e0';
update exercises set default_variation_id = 'bbaa7d0e-7333-5ed8-93d7-ec71e62aa5a5' where id = 'ebb66e5b-cad9-5bb6-8328-6704f9185ef2';
update exercises set default_variation_id = '6a5059a7-c2ce-567c-910e-5be4cf93c410' where id = '51796dba-51ed-5dba-a180-a247815fcce7';
update exercises set default_variation_id = '7d36fec2-8ed6-5592-bca6-c02ed2a4e3f7' where id = '1b15e740-6496-5756-919c-ee204447f564';
update exercises set default_variation_id = 'e897f9a4-f6da-5cf1-ab59-95631fd5240f' where id = '63eeda9c-cc67-59a5-aea4-e1905771ad43';
update exercises set default_variation_id = '54b70526-d339-52c7-9b58-6994994a34a7' where id = 'fa1b32d9-b984-542b-843a-1ceaeecacd79';
update exercises set default_variation_id = '17953199-99e3-5c80-acf4-3984153c255c' where id = '1b6e5da3-39d0-5b0b-8cd8-55c53e6497cd';
update exercises set default_variation_id = 'fd6b4897-173c-5cdf-9fc9-26841dabb444' where id = '2c796f45-cea6-5c1e-87a0-0a3e6b35c8ab';
update exercises set default_variation_id = '6342839f-3025-405c-977a-da849d1b1083' where id = '908a7e05-0635-4aaf-8de7-5a9eed2e91f9';
update exercises set default_variation_id = '46c66bf8-d87b-52da-9238-7e301d024b7a' where id = '1aafd3da-bba6-55de-b050-0fbcceb61167';
update exercises set default_variation_id = '92d26f98-ce13-54de-a066-6818b2fd4bb7' where id = 'cf07b6a4-7854-5ede-a289-629253b759a6';
