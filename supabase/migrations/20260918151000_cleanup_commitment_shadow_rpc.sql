-- Remove somente o endpoint temporario de comparacao. As funcoes internas
-- antiga e otimizada permanecem disponiveis para reversao operacional.

drop function if exists public.get_commitment_overview_v2_shadow(
  date, date, text, text
);
