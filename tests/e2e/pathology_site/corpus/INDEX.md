# Oracle corpus index

All patients, names, ids and endpoints are made up. NHS numbers are 999xxxxxxx. Sender FAKESEND / NORTHFIELD TEST SITE, receiver FAKELIMS / TESTLAB ONE. Test codes are invented (TST01..TST08 known, ZZUNK unknown); values carry no meaning. Segment separator is CR. Files are raw bytes: Latin-1 files hold byte E8, UTF-8 files hold C3 A8. Read and send as bytes.

| File | Purpose |
|---|---|
| 01_orm_plain.hl7 | Plain ASCII order, baseline that should pass |
| 02_oru_3obx_plain.hl7 | Plain ASCII result with 3 OBX, baseline |
| 02_oru_5obx_plain.hl7 | Plain ASCII result with 5 OBX, baseline |
| 02_oru_8obx_plain.hl7 | Plain ASCII result with 8 OBX, baseline |
| 03_oru_3obx_unknown_at_2.hl7 | 3 OBX; OBX-2 carries code ZZUNK, not in any made-up map, others known |
| 03_oru_5obx_unknown_at_5.hl7 | 5 OBX; OBX-5 carries code ZZUNK, not in any made-up map, others known |
| 03_oru_8obx_unknown_at_1.hl7 | 8 OBX; OBX-1 carries code ZZUNK, not in any made-up map, others known |
| 03_oru_6obx_unknown_at_4.hl7 | 6 OBX; OBX-4 carries code ZZUNK, not in any made-up map, others known |
| 03_oru_all_known_4obx.hl7 | Control for the unknown-code files: 4 OBX, all codes known |
| 04_oru_e_grave_utf8_no18.hl7 | e-grave in PID-5, ORC-12, OBX-5 and NTE; bytes UTF-8 (C3 A8); MSH-18 empty |
| 04_oru_e_grave_latin1_no18.hl7 | Same fields; bytes Latin-1 (E8); MSH-18 empty |
| 04_oru_e_grave_utf8_with18.hl7 | Same fields; UTF-8 bytes; MSH-18 UNICODE UTF-8 |
| 04_oru_e_grave_latin1_with18.hl7 | Same fields; Latin-1 bytes; MSH-18 8859/1 |
| 04_oru_e_grave_latin1_declares_utf8.hl7 | Mismatch: Latin-1 bytes but MSH-18 says UTF-8 (invalid UTF-8 on the wire) |
| 04_orm_e_grave_utf8_no18.hl7 | Order with e-grave in PID-5 and NTE; UTF-8; MSH-18 empty |
| 04_orm_e_grave_latin1_no18.hl7 | Order with e-grave; Latin-1; MSH-18 empty |
| 04_orm_e_grave_utf8_with18.hl7 | Order with e-grave; UTF-8; MSH-18 set |
| 04_oru_plain_control.hl7 | Plain ASCII 4 OBX, to send beside the e-grave files to a receiver that refuses bytes above 0x7F |
| 05_seq_a1_order.hl7 | Sequence A step 1: order ORD040 |
| 05_seq_a2_order_duplicate.hl7 | Sequence A step 2: same order again, new control id (duplicate order) |
| 05_seq_a3_result.hl7 | Sequence A step 3: result for ORD040 |
| 05_seq_a4_result_duplicate.hl7 | Sequence A step 4: same result again, new control id (duplicate result) |
| 05_seq_a5_result_identical_ctl.hl7 | Sequence A step 5: byte-identical to step 3 including MSH-10 (exact resend) |
| 05_seq_b1_result_first.hl7 | Sequence B step 1, OUT OF ORDER: result for ORD041 sent before its order |
| 05_seq_b2_order_after.hl7 | Sequence B step 2: the order for ORD041, arriving after its result |
| 05_seq_c1_result_no_order.hl7 | Sequence C: result whose order is never sent (orphan) |
| 05_seq_d1_result_final.hl7 | Sequence D step 1: result (OBX-11 F) |
| 05_seq_d2_result_older_timestamp.hl7 | Sequence D step 2: same order, MSH-7 earlier than step 1 but sent after it (out-of-order by time) |
| 06_oru_6obx_unknown_at_3_e_grave_utf8_no18.hl7 | Combined: unknown code at OBX-3 and e-grave in PID-5; UTF-8; MSH-18 empty |
