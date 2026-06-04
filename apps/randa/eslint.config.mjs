import reactViteConfig from "@perx/eslint-config/react-vite";

export default [
  {
    ignores: [".next/**", "dist/**"],
  },
  ...reactViteConfig,
];
