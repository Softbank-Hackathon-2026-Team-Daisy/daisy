import { useState } from 'react'
import { getLangSetting, LANGS, setLangSetting, t, type LangSetting } from '../i18n/index.ts'
import Select from './Select.tsx'

// 화면 언어 고르기 (#75) — 언어 이름은 번역하지 않고 그 언어로 써요. 기본값은 브라우저 언어
function LanguageSelect() {
  const [value, setValue] = useState<LangSetting>(getLangSetting)
  const options = [{ value: 'system', label: t('브라우저 설정 따르기') }, ...LANGS]
  return (
    <Select
      label={t('언어')}
      value={value}
      options={options}
      onChange={(v) => {
        setValue(v as LangSetting)
        setLangSetting(v as LangSetting)
      }}
    />
  )
}

export default LanguageSelect
