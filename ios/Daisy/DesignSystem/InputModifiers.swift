import SwiftUI

extension View {
    /// 주소 입력칸: 자동 수정 · 대문자 끄기, iOS는 URL 키보드.
    func urlInput() -> some View {
        #if os(iOS)
        self.textContentType(.URL)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self.textContentType(.URL)
            .autocorrectionDisabled()
        #endif
    }

    /// 아이디 입력칸: 자동 수정 · 대문자 끄기.
    func plainInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }
}
