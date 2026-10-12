T-01 · plan nói 4 TTF static · thực tế chỉ có bản variable 1 file (277KB) từ google/fonts, không có static · dùng FontVariation('wght') trong T-01; không chạy được thì dừng hỏi user · orchestrator
T-05a · plan: owned không có code_input.dart · thực tế: thêm code_input.dart vào owned của T-05a (T-04 đã xong) để đổi nền khối code sang codeSurface/codeInk (INV-08) · orchestrator
T-01 · mockup chữ nút IN HOA · thực tế chỉ w900 + letterSpacing (toUpperCase làm vỡ find.text test cũ) · chấp nhận · orchestrator
T-03 · plan: ScreenHeader thêm ☰ · thêm: sửa Minor-1 của review T-01 (bóng nút vô hiệu theme sáng trùng màu nền, widgets.dart ~282,374-376 → Color.lerp(p.outline, Colors.black, 0.3)) vì T-03 sở hữu widgets.dart · orchestrator
